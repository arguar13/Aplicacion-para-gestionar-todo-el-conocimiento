import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Hasta cuánto mide una línea que se lee y se resalta entera (F25). Más
/// larga —un párrafo de un PDF o de un artículo suele venir en una sola
/// línea— se lee de a oraciones: resaltar diez renglones de pantalla a la
/// vez no dice por dónde va, y un pedazo corto empieza a sonar enseguida al
/// retomar o saltar. Unas tres o cuatro líneas de un teléfono.
const _kMaxSegmentLength = 280;

/// El mismo corte de oraciones de `splitIntoSpeechSegments`: la puntuación
/// queda pegada a la oración que cierra, y el espacio de después es lo que
/// separa —de ahí salen las posiciones exactas de cada oración—.
final _sentenceBoundary = RegExp(r'(?<=[.!?…])\s+');

/// La marca de tiempo al comienzo de una línea de transcripción, `[2:07]` o
/// `[1:02:07]`: la misma que reconoce `transcript_timestamps.dart`.
final _timestampLabel = RegExp(r'^\[\d{1,2}(?::\d{2}){1,2}\]\s*');

/// Si queda algo que se pronuncie: una línea de solo "---", "* * *" o una
/// marca de tiempo sin texto no se lee, ni se para en ella al saltar.
final _pronounceable = RegExp(r'[\p{L}\p{N}]', unicode: true);

final _whitespace = RegExp(r'\s+');

// --- Markdown ---------------------------------------------------------------

/// Una cerca de bloque de código, de apertura o de cierre.
final _codeFence = RegExp('^(?:```|~~~)');

/// Lo que va al comienzo de una línea y no se dice: el `#` de un título, el
/// `>` de una cita, la viñeta o el número de una lista —con su casilla, si
/// es una lista de tareas—. Se aplica de a uno, hasta que no quede ninguno:
/// una cita puede tener una lista adentro.
final _blockPrefix = RegExp(
  r'^(?:#{1,6}(?:\s+|$)|>\s?|(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?)',
);

/// `![texto](dirección)` y `![[archivo]]`: una imagen no se lee —su texto
/// alternativo suele ser el nombre del archivo—.
final _image = RegExp(r'!\[\[[^\]]*\]\]|!\[[^\]]*\]\([^)]*\)');

/// `[texto](dirección)`: se dice el texto, nunca la dirección.
final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');

/// `[[nota]]` o `[[nota|cómo se ve]]`: se dice lo que se ve.
final _wikiLink = RegExp(r'\[\[([^\]|]*)(?:\|([^\]]*))?\]\]');

/// La llamada a una nota al pie, `[^1]`.
final _footnoteRef = RegExp(r'\[\^[^\]]*\]');

/// Las marcas de negrita, tachado y código, que no tienen texto adentro que
/// cambie al sacarlas.
final _inlineMarks = RegExp(r'\*\*|__|~~|`');

/// `*cursiva*` y `_cursiva_`, solo pegadas a una palabra: así no se comen el
/// `*` de "2 * 3" ni el `_` de un nombre_de_archivo.
final _starEmphasis = RegExp(r'(?<![\w*])\*(?=\S)([^*]+?)(?<=\S)\*(?![\w*])');
final _underscoreEmphasis = RegExp(
  r'(?<![\p{L}\p{N}_])_(?=\S)([^_]+?)(?<=\S)_(?![\p{L}\p{N}_])',
  unicode: true,
);

/// Una etiqueta HTML suelta (`<br>`, `<sup>`): empieza con una letra, para no
/// tocar un "a < b".
final _htmlTag = RegExp('</?[a-zA-Z][^>]*>');

/// Un carácter escapado, `\*`: se dice el carácter.
final _escaped = RegExp(r'\\([\\`*_{}\[\]()#+\-.!>|~])');

/// Las partes de un texto que se ofrece para leer de una vez —ver
/// [documentFrom]—: un mensaje del chat, el frente o el dorso de una
/// tarjeta.
typedef ReadablePart = ({
  String sourceKey,
  String text,
  bool markdown,
  bool transcript,
});

/// Parte [raw] —el texto tal cual se guarda y se ve— en lo que el lector
/// flotante lee de una vez y resalta en amarillo (F25): **una línea por
/// pedazo**, y una línea de más de [_kMaxSegmentLength] caracteres, de a
/// oraciones.
///
/// `start` y `end` de cada pedazo son posiciones en [raw], sin los espacios
/// de los costados: lo que la pantalla pinta. `spoken` es lo mismo sin lo
/// que no se pronuncia: con [transcript], la marca "[3:15]" del comienzo de
/// la línea —que sí queda dentro del resaltado: es parte del renglón—; con
/// [markdown], los símbolos de formato. Un pedazo sin nada que decir no se
/// incluye.
List<ReadableSegment> buildReadableSegments(
  String raw, {
  required String sourceKey,
  bool transcript = false,
  bool markdown = false,
}) {
  final segments = <ReadableSegment>[];
  var inCodeBlock = false;
  var lineStart = 0;

  while (lineStart <= raw.length) {
    var lineEnd = raw.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = raw.length;

    final line = raw.substring(lineStart, lineEnd);
    final start = lineStart + line.length - line.trimLeft().length;
    final end = lineEnd - (line.length - line.trimRight().length);
    lineStart = lineEnd + 1;
    if (start >= end) continue;

    if (markdown && _codeFence.hasMatch(raw.substring(start, end))) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    // Dentro de un bloque de código no hay formato que sacar: un `*` o un
    // `#` ahí son parte de lo que dice.
    final stripMarkdown = markdown && !inCodeBlock;

    var firstOfLine = true;
    for (final (pieceStart, pieceEnd) in _pieces(raw, start, end)) {
      final spoken = _spoken(
        raw.substring(pieceStart, pieceEnd),
        lineStart: firstOfLine,
        transcript: transcript,
        markdown: stripMarkdown,
      );
      firstOfLine = false;
      if (spoken.isEmpty) continue;
      segments.add(
        ReadableSegment(
          sourceKey: sourceKey,
          start: pieceStart,
          end: pieceEnd,
          spoken: spoken,
        ),
      );
    }
  }
  return segments;
}

/// Un documento hecho de varios textos en pantalla, uno detrás del otro: los
/// mensajes de una conversación, el frente y el dorso de una tarjeta (F25).
/// Cada pedazo recuerda de qué texto salió, para que cada uno se resalte en
/// su lugar.
ReadableDocument documentFrom(
  String id,
  String title,
  List<ReadablePart> parts,
) => ReadableDocument(
  id: id,
  title: title,
  segments: [
    for (final part in parts)
      ...buildReadableSegments(
        part.text,
        sourceKey: part.sourceKey,
        transcript: part.transcript,
        markdown: part.markdown,
      ),
  ],
);

/// Los tramos `[start, end)` de [raw] en que se lee la línea `[start, end)`:
/// ella entera si es corta; si no, sus oraciones —y una oración que todavía
/// es muy larga, cortada en el último espacio antes del límite, como
/// `_hardSplit` de `speech_segmentation.dart`—. Cada tramo, sin espacios a
/// los costados.
Iterable<(int, int)> _pieces(String raw, int start, int end) sync* {
  if (end - start <= _kMaxSegmentLength) {
    yield (start, end);
    return;
  }
  var sentenceStart = start;
  final line = raw.substring(start, end);
  for (final boundary in _sentenceBoundary.allMatches(line)) {
    yield* _hardSplit(raw, sentenceStart, start + boundary.start);
    sentenceStart = start + boundary.end;
  }
  yield* _hardSplit(raw, sentenceStart, end);
}

Iterable<(int, int)> _hardSplit(String raw, int start, int end) sync* {
  var from = start;
  while (end - from > _kMaxSegmentLength) {
    var cut = raw.lastIndexOf(' ', from + _kMaxSegmentLength);
    // Sin un espacio en el tramo —una dirección larguísima—: se corta en
    // el límite; partir esa "palabra" es menos malo que leerla entera.
    if (cut <= from) cut = from + _kMaxSegmentLength;
    var pieceEnd = cut;
    while (pieceEnd > from && _isSpace(raw[pieceEnd - 1])) {
      pieceEnd--;
    }
    yield (from, pieceEnd);
    from = cut;
    while (from < end && _isSpace(raw[from])) {
      from++;
    }
  }
  if (from < end) yield (from, end);
}

bool _isSpace(String char) => char.trim().isEmpty;

/// Lo que se le dice al motor de voz de [text]: sin lo que no se pronuncia,
/// con los espacios juntados en uno —un tabulador o tres espacios no
/// cambian cómo suena, pero sí cuánto "mide" para los ±10 s—. Vacío si no
/// queda nada que decir.
String _spoken(
  String text, {
  required bool lineStart,
  required bool transcript,
  required bool markdown,
}) {
  var spoken = text;
  if (transcript && lineStart) {
    spoken = spoken.replaceFirst(_timestampLabel, '');
  }
  if (markdown) spoken = _stripMarkdown(spoken, lineStart: lineStart);
  spoken = spoken.replaceAll(_whitespace, ' ').trim();
  return _pronounceable.hasMatch(spoken) ? spoken : '';
}

String _stripMarkdown(String text, {required bool lineStart}) {
  var stripped = text;
  if (lineStart) {
    while (true) {
      final prefix = _blockPrefix.firstMatch(stripped);
      if (prefix == null || prefix.end == 0) break;
      stripped = stripped.substring(prefix.end);
    }
    // Una fila de tabla: las celdas se leen separadas por una pausa, no
    // pegadas ni con "barra" en el medio.
    if (stripped.startsWith('|')) {
      stripped = stripped
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .join(', ');
    }
  }
  return stripped
      .replaceAll(_image, '')
      .replaceAllMapped(_link, (m) => m[1]!)
      .replaceAllMapped(_wikiLink, (m) => m[2] ?? m[1]!)
      .replaceAll(_footnoteRef, '')
      .replaceAll(_htmlTag, '')
      .replaceAll(_inlineMarks, '')
      .replaceAllMapped(_starEmphasis, (m) => m[1]!)
      .replaceAllMapped(_underscoreEmphasis, (m) => m[1]!)
      .replaceAllMapped(_escaped, (m) => m[1]!);
}
