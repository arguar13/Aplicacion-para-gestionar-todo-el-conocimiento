import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';

/// Qué encontró mal la verificación en una fuente.
enum ChunkInvariantProblem {
  /// `fullText` tiene contenido pero la fuente no tiene ningún chunk.
  missingChunks,

  /// `seq` no es 0, 1, 2… sin huecos ni repetidos.
  seqNotContiguous,

  /// Concatenar los chunks en orden NO reproduce `fullText` — el
  /// invariante central del encargo.
  textMismatch,

  /// `charStart`/`charEnd` no describen una partición exacta de
  /// `fullText`, o un chunk no es literalmente
  /// `fullText.substring(charStart, charEnd)`.
  offsetsInconsistent,
}

class ChunkInvariantViolation {
  const ChunkInvariantViolation({
    required this.itemId,
    required this.problem,
    required this.detail,
  });

  final String itemId;
  final ChunkInvariantProblem problem;

  /// Sin el texto en sí —puede ser larguísimo y personal—: solo largos y
  /// posiciones.
  final String detail;

  @override
  String toString() => '$itemId: ${problem.name} ($detail)';
}

/// Resultado de verificar el invariante de reconstrucción sobre toda la
/// bóveda.
class ChunkInvariantReport {
  const ChunkInvariantReport({
    required this.sourcesChecked,
    required this.sourcesWithoutText,
    required this.chunksChecked,
    required this.violations,
  });

  /// Fuentes con texto: las que de verdad se comprobaron.
  final int sourcesChecked;

  /// Fuentes sin texto —todavía sin procesar, o vacías—:
  /// ni pasan ni fallan, y se cuentan aparte para que un antes/después
  /// (F10) pueda comprobar que no cambió.
  final int sourcesWithoutText;

  final int chunksChecked;
  final List<ChunkInvariantViolation> violations;

  bool get holds => violations.isEmpty;

  String summary() =>
      '$sourcesChecked fuentes con texto, $chunksChecked chunks, '
      '$sourcesWithoutText fuentes sin texto: '
      '${holds ? 'invariante OK' : '${violations.length} violaciones'}';
}

/// Verifica, sobre TODA la bóveda, que concatenar los chunks de cada
/// fuente —en orden de `seq`— reproduce su `fullText` carácter a
/// carácter, y que los offsets de cada chunk lo describen de verdad.
///
/// Es la restricción inalienable del encargo (nada de resumir ni perder
/// texto de una fuente), hecha comprobable en cualquier momento: la corren
/// los tests de cierre de cada fase y la usará F10 después de migrar de
/// modelo. Solo lee: no corrige nada. Ante un problema, informa cuál y en
/// qué fuente, y quien llama decide.
Future<ChunkInvariantReport> verifyChunkInvariant(AppDatabase db) async {
  // Primero solo los ids, y el `fullText` de a una fuente: cargar todos
  // los textos de una bóveda grande de una sola vez sería el problema.
  final itemIds =
      await (db.selectOnly(db.knowledgeSources)
            ..addColumns([db.knowledgeSources.itemId])
            ..orderBy([OrderingTerm(expression: db.knowledgeSources.itemId)]))
          .map((row) => row.read(db.knowledgeSources.itemId)!)
          .get();

  var sourcesChecked = 0;
  var sourcesWithoutText = 0;
  var chunksChecked = 0;
  final violations = <ChunkInvariantViolation>[];

  for (final itemId in itemIds) {
    // El texto íntegro es el de la forma de texto principal: F10 lo guarda una
    // sola vez, y los chunks se comprueban contra él.
    final fullText = (await sourceTextRendition(db, itemId))?.content ?? '';

    if (fullText.isEmpty) {
      sourcesWithoutText++;
      continue;
    }

    final chunks =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals(itemId))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
            .get();

    sourcesChecked++;
    chunksChecked += chunks.length;
    violations.addAll(_checkSource(itemId, fullText, chunks));
  }

  return ChunkInvariantReport(
    sourcesChecked: sourcesChecked,
    sourcesWithoutText: sourcesWithoutText,
    chunksChecked: chunksChecked,
    violations: violations,
  );
}

List<ChunkInvariantViolation> _checkSource(
  String itemId,
  String fullText,
  List<ChunkRow> chunks,
) {
  if (chunks.isEmpty) {
    return [
      ChunkInvariantViolation(
        itemId: itemId,
        problem: ChunkInvariantProblem.missingChunks,
        detail: 'fullText de ${fullText.length} caracteres sin ningún chunk',
      ),
    ];
  }

  final violations = <ChunkInvariantViolation>[];

  for (var i = 0; i < chunks.length; i++) {
    if (chunks[i].seq != i) {
      violations.add(
        ChunkInvariantViolation(
          itemId: itemId,
          problem: ChunkInvariantProblem.seqNotContiguous,
          detail: 'en la posición $i hay seq ${chunks[i].seq}',
        ),
      );
      break;
    }
  }

  final rebuilt = StringBuffer();
  for (final chunk in chunks) {
    rebuilt.write(chunk.content);
  }
  final rebuiltText = rebuilt.toString();
  if (rebuiltText != fullText) {
    violations.add(
      ChunkInvariantViolation(
        itemId: itemId,
        problem: ChunkInvariantProblem.textMismatch,
        detail:
            'fullText tiene ${fullText.length} caracteres y los chunks '
            'reconstruyen ${rebuiltText.length}; primera diferencia en '
            '${_firstDifference(fullText, rebuiltText)}',
      ),
    );
  }

  final offsetsProblem = _offsetsProblem(fullText, chunks);
  if (offsetsProblem != null) {
    violations.add(
      ChunkInvariantViolation(
        itemId: itemId,
        problem: ChunkInvariantProblem.offsetsInconsistent,
        detail: offsetsProblem,
      ),
    );
  }

  return violations;
}

/// `null` si los offsets describen una partición exacta de [fullText];
/// si no, qué chunk es el primero que se sale.
String? _offsetsProblem(String fullText, List<ChunkRow> chunks) {
  var expectedStart = 0;
  for (final chunk in chunks) {
    if (chunk.charStart != expectedStart) {
      return 'chunk ${chunk.seq}: charStart ${chunk.charStart}, se esperaba '
          '$expectedStart';
    }
    if (chunk.charEnd < chunk.charStart || chunk.charEnd > fullText.length) {
      return 'chunk ${chunk.seq}: charEnd ${chunk.charEnd} fuera de rango '
          '(0..${fullText.length})';
    }
    if (fullText.substring(chunk.charStart, chunk.charEnd) != chunk.content) {
      return 'chunk ${chunk.seq}: su texto no es fullText entre '
          '${chunk.charStart} y ${chunk.charEnd}';
    }
    expectedStart = chunk.charEnd;
  }

  if (expectedStart != fullText.length) {
    return 'los chunks cubren $expectedStart de ${fullText.length} '
        'caracteres';
  }
  return null;
}

int _firstDifference(String a, String b) {
  final shortest = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shortest; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return i;
  }
  return shortest;
}
