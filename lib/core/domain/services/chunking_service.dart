import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

/// Un fragmento del texto íntegro de una fuente, con su posición exacta en
/// el original.
///
/// No es una reducción: `text` es la porción literal de `fullText` entre
/// [charStart] y [charEnd], sin recortar ni normalizar. Ver
/// [chunkingInvariantHolds].
@immutable
class TextChunk {
  const TextChunk({
    required this.seq,
    required this.text,
    required this.charStart,
    required this.charEnd,
    this.startMs,
    this.endMs,
    this.pageNumber,
    this.headingPath,
  });

  /// Orden estricto desde 0 dentro de la misma fuente.
  final int seq;

  final String text;

  /// Offset en `fullText`, en unidades UTF-16 de Dart (lo mismo que usa
  /// `String.substring`). Inclusive.
  final int charStart;

  /// Igual que [charStart], exclusive.
  final int charEnd;

  /// Cuándo empieza este fragmento en el audio/video de origen, si la
  /// fuente trae marcas de tiempo.
  final int? startMs;

  /// Cuándo termina. `null` en el último fragmento: el formato de
  /// transcripción guardado (`[mm:ss] texto`) marca el instante en que
  /// empieza cada línea, no cuánto dura — "hasta dónde llega" el último
  /// fragmento no es un dato que exista.
  final int? endMs;

  final int? pageNumber;

  /// "Cap. 3 > Sección 2", cuando se sepa. Ningún productor de chunks de
  /// esta versión lo completa todavía; el campo existe porque `chunk` en la
  /// base ya lo prevé para libros paginados.
  final String? headingPath;
}

/// Verifica el invariante central del chunking: concatenar el texto de
/// [chunks], en el orden de [TextChunk.seq], reproduce [fullText] carácter
/// a carácter.
///
/// Vive acá y no solo en el test porque la migración que puebla `chunk`
/// (ver `backfill_knowledge_model_v8.dart`) la necesita en tiempo de
/// ejecución: una fuente cuyo texto no reconstruye exacto no se fragmenta,
/// se reporta en `migration_issue` y se sigue con la siguiente — nunca se
/// persiste un chunk que no cumple esto.
bool chunkingInvariantHolds(String fullText, List<TextChunk> chunks) {
  final buffer = StringBuffer();
  for (final chunk in chunks) {
    buffer.write(chunk.text);
  }
  return buffer.toString() == fullText;
}

/// Cuánto dura, como mínimo, la ventana de una transcripción antes de
/// buscar dónde cerrarla en un límite de oración.
const _transcriptWindowMs = 75000;

/// Cuántas líneas más allá del umbral se miran buscando un cierre de
/// oración, antes de cerrar el grupo igual en el umbral.
const _transcriptCloseLookaheadLines = 5;

final _timestampLinePattern = RegExp(r'^\[(\d+):(\d{2})(?::(\d{2}))?\] ');
final _sentenceEndPattern = RegExp(r'[.!?…]$');
final _paragraphSeparatorPattern = RegExp('\n{2,}');

/// Parte el texto íntegro de una fuente en fragmentos ordenados —para
/// indexar, no para reducir.
///
/// El punto central de todo el diseño: quien fragmenta decide DÓNDE
/// cortar, nunca reescribe lo que queda de cada lado. Cada
/// [TextChunk.text] es literalmente `fullText.substring(charStart,
/// charEnd)`, así que la reconstrucción es una propiedad aritmética de
/// `substring` y no algo que este servicio tenga que "lograr" — ver
/// `chunking_service_test.dart`, que lo verifica sobre cada estrategia.
///
/// Clase concreta y no una interfaz inyectable: es lógica pura y
/// determinística, sin nada que dependa de la plataforma ni que un test
/// necesite doblar — mismo criterio que `encodeContentBlocks` o
/// `formatTranscript` en el resto del proyecto.
class ChunkingService {
  const ChunkingService();

  /// Parte [fullText] en fragmentos.
  ///
  /// Con [paged], el texto viene de un PDF cuyas páginas están separadas por
  /// `---` en una línea propia, una por segmento —páginas en blanco incluidas,
  /// vacías—: cada fragmento sabe entonces en qué página está
  /// ([TextChunk.pageNumber]). Solo tiene sentido si el texto se generó así;
  /// con otro texto —un artículo, un EPUB cuyos capítulos se separan igual—
  /// numeraría algo que no son páginas, y un número de página equivocado es
  /// peor que ninguno.
  List<TextChunk> chunk(
    String fullText, {
    required RenditionKind kind,
    bool paged = false,
  }) {
    if (fullText.isEmpty) return const [];

    if (kind == RenditionKind.blocks) return _chunkBlocks(fullText);
    if (_looksLikeTimedTranscript(fullText)) {
      return _chunkTimedTranscript(fullText);
    }
    final chunks = _chunkByParagraph(fullText);
    return paged ? _numberPages(chunks) : chunks;
  }

  /// Le pone a cada fragmento la página en la que está: la primera empieza en 1
  /// y cada separador de página (`---`) abre la siguiente. El propio separador
  /// pertenece a la página que cierra.
  List<TextChunk> _numberPages(List<TextChunk> chunks) {
    var page = 1;
    final numbered = <TextChunk>[];
    for (final chunk in chunks) {
      numbered.add(
        TextChunk(
          seq: chunk.seq,
          text: chunk.text,
          charStart: chunk.charStart,
          charEnd: chunk.charEnd,
          pageNumber: page,
        ),
      );
      if (chunk.text.trim() == '---') page++;
    }
    return numbered;
  }

  /// Corta en cada línea en blanco (`\n` repetido). El separador queda
  /// pegado al fragmento anterior, así el corte siempre cae justo después
  /// de él, sin ambigüedad de a quién pertenece.
  ///
  /// Un texto sin ninguna línea en blanco —un PDF escaneado por OCR, por
  /// ejemplo— da un solo fragmento entero: es correcto, no rompe el
  /// invariante. Subdividir párrafos larguísimos por oración es un
  /// refinamiento de una fase futura, no algo que F1 necesite resolver a
  /// la vez que la reconstrucción exacta.
  List<TextChunk> _chunkByParagraph(String fullText) {
    final chunks = <TextChunk>[];
    var start = 0;
    var seq = 0;

    for (final match in _paragraphSeparatorPattern.allMatches(fullText)) {
      final end = match.end;
      chunks.add(
        TextChunk(
          seq: seq++,
          text: fullText.substring(start, end),
          charStart: start,
          charEnd: end,
        ),
      );
      start = end;
    }

    if (start < fullText.length) {
      chunks.add(
        TextChunk(
          seq: seq++,
          text: fullText.substring(start),
          charStart: start,
          charEnd: fullText.length,
        ),
      );
    }

    return chunks;
  }

  /// Si la mayoría de las líneas empiezan con una marca `[mm:ss]` o
  /// `[h:mm:ss]` —el formato que guarda `formatTranscript` en
  /// `youtube_transcript_transformer.dart`—, es una transcripción con
  /// tiempo. Se decide por contenido y no por [RenditionKind]: tanto un
  /// artículo web como una transcripción de YouTube llegan como
  /// `markdown`.
  bool _looksLikeTimedTranscript(String fullText) {
    final lines = fullText.split('\n');
    if (lines.isEmpty) return false;

    final timedLines = lines.where(_timestampLinePattern.hasMatch).length;
    return timedLines * 2 > lines.length;
  }

  /// Agrupa líneas consecutivas hasta acumular ~75s, cerrando en una
  /// oración cuando aparece una dentro del margen de
  /// [_transcriptCloseLookaheadLines] líneas — igual que pide la sección 7
  /// del encargo ("respetando límites de oración"). El corte siempre cae
  /// justo después de un salto de línea, nunca a mitad de una: mismo
  /// principio que el chunking por párrafo.
  List<TextChunk> _chunkTimedTranscript(String fullText) {
    final lineStarts = <int>[0];
    for (var i = 0; i < fullText.length; i++) {
      if (fullText[i] == '\n') lineStarts.add(i + 1);
    }
    final lineCount = lineStarts.length;

    int lineEndOf(int lineIndex) =>
        lineIndex + 1 < lineCount ? lineStarts[lineIndex + 1] : fullText.length;

    String lineTextOf(int lineIndex) =>
        fullText.substring(lineStarts[lineIndex], lineEndOf(lineIndex));

    final lineStartMs = List<int?>.generate(lineCount, (i) {
      final match = _timestampLinePattern.firstMatch(lineTextOf(i));
      return match == null ? null : _parseTimestampMs(match);
    });

    // La primera línea con marca de tiempo ancla el resto: si el texto
    // empieza con líneas sin marca (encabezado, nota del usuario), quedan
    // en el primer grupo igual, arrastradas hasta la primera que sí la
    // tenga.
    final firstKnownMs = lineStartMs.firstWhere(
      (ms) => ms != null,
      orElse: () => 0,
    );

    final chunks = <TextChunk>[];
    var seq = 0;
    var groupStart = 0;

    while (groupStart < lineCount) {
      final groupStartMs = lineStartMs[groupStart] ?? firstKnownMs ?? 0;

      var closeAt = groupStart;
      while (closeAt < lineCount - 1) {
        final nextMs = lineStartMs[closeAt + 1];
        if (nextMs != null && nextMs - groupStartMs >= _transcriptWindowMs) {
          break;
        }
        closeAt++;
      }

      // Ya se cruzó el umbral (o se llegó al final): buscar, desde acá,
      // una línea que cierre en punto/exclamación/interrogación/puntos
      // suspensivos dentro del margen permitido.
      final lookaheadLimit = (closeAt + _transcriptCloseLookaheadLines).clamp(
        0,
        lineCount - 1,
      );
      for (var k = closeAt; k <= lookaheadLimit; k++) {
        final trimmed = lineTextOf(k).trimRight();
        if (trimmed.isNotEmpty && _sentenceEndPattern.hasMatch(trimmed)) {
          closeAt = k;
          break;
        }
      }

      final charStart = lineStarts[groupStart];
      final charEnd = lineEndOf(closeAt);

      chunks.add(
        TextChunk(
          seq: seq++,
          text: fullText.substring(charStart, charEnd),
          charStart: charStart,
          charEnd: charEnd,
          startMs: groupStartMs,
        ),
      );

      groupStart = closeAt + 1;
    }

    // Cada fragmento "termina" donde empieza el siguiente — ver el
    // comentario de [TextChunk.endMs].
    for (var i = 0; i < chunks.length - 1; i++) {
      final next = chunks[i + 1];
      final current = chunks[i];
      chunks[i] = TextChunk(
        seq: current.seq,
        text: current.text,
        charStart: current.charStart,
        charEnd: current.charEnd,
        startMs: current.startMs,
        endMs: next.startMs,
      );
    }

    return chunks;
  }

  int _parseTimestampMs(RegExpMatch match) {
    final thirdGroup = match.group(3);
    final int totalSeconds;
    if (thirdGroup != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = int.parse(thirdGroup);
      totalSeconds = hours * 3600 + minutes * 60 + seconds;
    } else {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      totalSeconds = minutes * 60 + seconds;
    }
    return totalSeconds * 1000;
  }

  /// Un fragmento por bloque de una nota armada con bloques
  /// (`encodeContentBlocks`/`decodeContentBlocks` en `content_block.dart`).
  ///
  /// No reconstruye el formato a mano asumiendo cómo separa sus elementos
  /// `jsonEncode`: en cambio, decodifica la lista y vuelve a codificar cada
  /// elemento por separado para encontrar su posición exacta dentro del
  /// texto completo con `indexOf`. Es más robusto que asumir comas sin
  /// espacio entre elementos — si `dart:convert` cambiara ese detalle,
  /// esto lo sigue encontrando bien, y si no lo encuentra, la excepción
  /// llega a la migración, que reporta la fila en vez de persistir un
  /// chunk mal cortado.
  List<TextChunk> _chunkBlocks(String fullText) {
    final decoded = jsonDecode(fullText) as List<dynamic>;
    if (decoded.isEmpty) return const [];

    final chunks = <TextChunk>[];
    var cursor = 0;

    for (var i = 0; i < decoded.length; i++) {
      final elementJson = jsonEncode(decoded[i]);
      final elementStart = fullText.indexOf(elementJson, cursor);
      if (elementStart < 0) {
        throw StateError(
          'No se encontró la serialización del bloque $i dentro del JSON '
          'completo — el chunking de bloques asume que jsonEncode es '
          'determinístico entre una decodificación y su recodificación.',
        );
      }
      final elementEnd = elementStart + elementJson.length;

      final isLast = i == decoded.length - 1;
      final separatorEnd = isLast
          ? elementEnd +
                1 // el ']' de cierre
          : fullText.indexOf(',', elementEnd) + 1;

      chunks.add(
        TextChunk(
          seq: i,
          text: fullText.substring(cursor, separatorEnd),
          charStart: cursor,
          charEnd: separatorEnd,
        ),
      );
      cursor = separatorEnd;
    }

    return chunks;
  }
}
