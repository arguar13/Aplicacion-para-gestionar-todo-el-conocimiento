import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/services/creation_scope_resolver.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/services/processed_card_text.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';

/// Arma el material de una creación (F43, punto 6 del plan): lo que entra en
/// la ventana del modelo elegido, de las fuentes que quedaron tildadas.
///
/// En el orden del plan, el primero que entra entero en
/// [CreationBudget.inputChars]:
///
/// 1. **el texto entero** de cada fuente —su texto procesado
///    (`ProcessedRepository.studyTextOf`), o, sin «Texto», lo que tiene para
///    leer (`readProcessedCardText`)—;
/// 2. **las oraciones del resumen** de cada una (las que ya marcó F36, en el
///    orden del texto), o su texto si no tiene resumen;
/// 3. **las de la síntesis**, o su resumen, o su texto;
/// 4. **por partes**: el texto más corto del punto 3, cortado en partes de
///    [CreationBudget.partChars], y como mucho [kMaxCreationParts] repartidas
///    a lo largo de todo el texto.
///
/// Cada fuente va bajo su título («## Éxodo»). Un libro de tres millones de
/// caracteres funciona igual con Gemma que con Gemini: solo cambia cuánto se
/// lee de primera mano ([CreationMaterial.coverage]).
///
/// **Nada pesado en el hilo de la interfaz**: juntar las páginas de un libro lo
/// hace `studyTextOf` en otro hilo; cortarlo en partes también va por
/// [ProcessedWorker] —en otro hilo desde [kProcessedInlineChars]—, y el texto
/// entero de un libro que no entra nunca se concatena: solo se suman largos.
class CreationMaterialBuilder {
  CreationMaterialBuilder({
    required ProcessedRepository processed,
    required CreationScopeResolver scopes,
    ProcessedWorker worker = runProcessedWork,
  }) : _processed = processed,
       _scopes = scopes,
       _worker = worker;

  final ProcessedRepository _processed;
  final CreationScopeResolver _scopes;
  final ProcessedWorker _worker;

  /// El material de [sourceIds] para [budget]. Las fuentes que ya no son
  /// procesados vivos se saltean; sin ninguna con texto, el material queda
  /// vacío ([CreationMaterial.isEmpty]) y quien lo pidió decide qué decir.
  Future<Either<Failure, CreationMaterial>> build({
    required List<String> sourceIds,
    required CreationBudget budget,
  }) async {
    final unique = <String>{...sourceIds}.toList();
    final described = await _scopes.sourcesOf(unique);
    if (described.isLeft()) return left(described.getLeft().toNullable()!);
    final sources = [
      for (final source in described.getRight().toNullable()!)
        if (source.isLive) source,
    ];

    final texts = <_SourceTexts>[];
    for (final source in sources) {
      final read = await _textsOf(source);
      if (read.isLeft()) return left(read.getLeft().toNullable()!);
      final texts0 = read.getRight().toNullable()!;
      if (texts0.full.trim().isNotEmpty) texts.add(texts0);
    }
    final withoutMarks = [
      for (final source in sources)
        if (!source.hasSummary && !source.hasSynthesis) source.documentId,
    ];
    if (texts.isEmpty) {
      return right(
        CreationMaterial(
          mode: CreationMaterialMode.fullText,
          sources: const [],
          text: '',
          withoutStudyMarks: withoutMarks,
        ),
      );
    }

    // De una vez, el primero que entra: solo se suman largos, sin armar nada.
    for (final (mode, level) in const [
      (CreationMaterialMode.fullText, _Level.full),
      (CreationMaterialMode.summarySentences, _Level.summary),
      (CreationMaterialMode.synthesisSentences, _Level.synthesis),
    ]) {
      final length = texts.fold<int>(
        0,
        (sum, t) => sum + _headed(t.title, '').length + 2 + t.at(level).length,
      );
      if (length <= budget.inputChars) {
        final pieces = [for (final t in texts) _headed(t.title, t.at(level))];
        // Dónde empieza cada fuente, con los dos saltos que las separan.
        final starts = <int>[];
        var at = 0;
        for (final piece in pieces) {
          starts.add(at);
          at += piece.length + 2;
        }
        return right(
          CreationMaterial(
            mode: mode,
            text: pieces.join('\n\n'),
            sourceStarts: starts,
            sources: [
              for (final t in texts)
                CreationMaterialSource(
                  documentId: t.documentId,
                  title: t.title,
                  chars: t.at(level).length,
                ),
            ],
            withoutStudyMarks: withoutMarks,
          ),
        );
      }
    }

    // Por partes, del texto más corto de cada una.
    final all = <CreationMaterialPart>[];
    for (final t in texts) {
      final body = t.at(_Level.synthesis);
      final header = _headed(t.title, '');
      final chunks = await _worker(splitCreationText, (
        text: body,
        maxChars: budget.partChars - header.length,
      ), size: body.length);
      for (final chunk in chunks) {
        all.add(
          CreationMaterialPart(
            documentId: t.documentId,
            text: _headed(t.title, chunk),
            index: all.length,
          ),
        );
      }
    }
    final chosen = pickEvenly(all, kMaxCreationParts);
    final allChars = all.fold<int>(0, (sum, p) => sum + p.text.length);
    final chosenChars = chosen.fold<int>(0, (sum, p) => sum + p.text.length);
    final base = texts.every((t) => t.synthesis != null)
        ? CreationPartsBase.synthesis
        : texts.every((t) => t.synthesis != null || t.summary != null)
        ? CreationPartsBase.summary
        : CreationPartsBase.fullText;
    return right(
      CreationMaterial(
        mode: CreationMaterialMode.byParts,
        parts: chosen,
        partsBase: base,
        totalParts: all.length,
        coverage: allChars == 0 ? 1 : chosenChars / allChars,
        sources: [
          for (final t in texts)
            CreationMaterialSource(
              documentId: t.documentId,
              title: t.title,
              chars: [
                for (final p in chosen)
                  if (p.documentId == t.documentId) p.text.length,
              ].fold(0, (sum, n) => sum + n),
            ),
        ],
        withoutStudyMarks: withoutMarks,
      ),
    );
  }

  /// Los tres textos de [source]: el entero, el del resumen y el de la
  /// síntesis (estos dos, `null` si no los tiene).
  Future<Either<Failure, _SourceTexts>> _textsOf(CreationSource source) async {
    final id = source.documentId;
    final study = await _processed.studyTextOf(id);
    if (study.isLeft()) return left(study.getLeft().toNullable()!);
    var full = study.getRight().toNullable()?.content;
    if (full == null || full.trim().isEmpty) {
      // Sin «Texto» ni copia del original: lo que tiene para leer —sus notas,
      // sus fragmentos, lo elegido—, como sus tarjetas.
      final card = await readProcessedCardText(_processed, id);
      if (card.isLeft()) return left(card.getLeft().toNullable()!);
      full = card.getRight().toNullable()?.content ?? '';
    }
    Future<Either<Failure, String?>> sentences(ProcessedSection section) async {
      final parts = await _processed.partsOf(id, sections: {section});
      return parts.map((parts) {
        final lines = [
          for (final part in parts)
            if (part.content.trim().isNotEmpty) part.content.trim(),
        ];
        return lines.isEmpty ? null : lines.join('\n');
      });
    }

    String? summary;
    if (source.hasSummary) {
      final read = await sentences(ProcessedSection.summary);
      if (read.isLeft()) return left(read.getLeft().toNullable()!);
      summary = read.getRight().toNullable();
    }
    String? synthesis;
    if (source.hasSynthesis) {
      final read = await sentences(ProcessedSection.synthesis);
      if (read.isLeft()) return left(read.getLeft().toNullable()!);
      synthesis = read.getRight().toNullable();
    }
    return right(
      _SourceTexts(
        documentId: id,
        title: source.title,
        full: full,
        summary: summary,
        synthesis: synthesis,
      ),
    );
  }

  static String _headed(String title, String body) => '## $title\n\n$body';
}

enum _Level { full, summary, synthesis }

class _SourceTexts {
  const _SourceTexts({
    required this.documentId,
    required this.title,
    required this.full,
    this.summary,
    this.synthesis,
  });

  final String documentId;
  final String title;
  final String full;
  final String? summary;
  final String? synthesis;

  /// El texto de [level], o el más largo que tenga: sin síntesis, el resumen;
  /// sin resumen, el entero.
  String at(_Level level) => switch (level) {
    _Level.full => full,
    _Level.summary => summary ?? full,
    _Level.synthesis => synthesis ?? summary ?? full,
  };
}

/// Corta [input].text en tramos de a lo sumo [input].maxChars caracteres, sin
/// partir palabras si se puede: cada corte busca, hacia atrás desde el tope, un
/// fin de párrafo, después un fin de oración y después un espacio; solo si no
/// hay ninguno en la segunda mitad del tramo, corta en el tope. Sin tramos en
/// blanco.
///
/// Es una función de nivel superior a propósito: corre en otro hilo
/// (`compute`) con un libro entero.
List<String> splitCreationText(({String text, int maxChars}) input) {
  final text = input.text;
  final max = input.maxChars < 1 ? 1 : input.maxChars;
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = start + max;
    if (end >= text.length) {
      end = text.length;
    } else {
      final floor = start + max ~/ 2;
      final cut =
          _lastBreak(text, '\n\n', floor, end) ??
          _lastSentenceEnd(text, floor, end) ??
          _lastBreak(text, ' ', floor, end);
      if (cut != null) end = cut;
    }
    final chunk = text.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
  }
  return chunks;
}

/// Dónde termina la última aparición de [mark] que empieza en `[floor, end)`.
int? _lastBreak(String text, String mark, int floor, int end) {
  final at = text.lastIndexOf(mark, end - mark.length);
  return at >= floor ? at + mark.length : null;
}

/// Dónde termina la última oración —un `.`, `?` o `!` seguido de espacio—
/// dentro de `[floor, end)`.
int? _lastSentenceEnd(String text, int floor, int end) {
  for (var i = end - 1; i > floor; i--) {
    final c = text.codeUnitAt(i - 1);
    if ((c == 0x2E || c == 0x3F || c == 0x21) && text.codeUnitAt(i) == 0x20) {
      return i + 1;
    }
  }
  return null;
}

/// A lo sumo [max] de [all], repartidos parejo de punta a punta y en orden: la
/// primera y la última siempre, y las del medio a la misma distancia.
List<T> pickEvenly<T>(List<T> all, int max) {
  if (all.length <= max) return all;
  if (max <= 0) return const [];
  if (max == 1) return [all.first];
  return [
    for (var k = 0; k < max; k++)
      all[(k * (all.length - 1) / (max - 1)).round()],
  ];
}
