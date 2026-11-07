/// Lo que se lee de un texto en Markdown, sin sus marcas (F46, paso 5e): lo
/// que viaja al chat y al modelo cuando sale de un documento.
///
/// Existe porque «Preguntar al chat» del Índice y «Explicar» de las tarjetas
/// cortaban del Markdown crudo de una página web, y el borrador del chat
/// llevaba `[Frederick Frost Blackman](https://es.wikipedia.org/wiki/…)`, las
/// fotos con sus direcciones larguísimas y las notas al pie `[[1]](…)`: lo veía
/// la persona en el campo y lo recibía el modelo, y las direcciones se comían
/// el tope de letras del pasaje.
///
/// **Lo en línea lo dice el lector.** Qué es una construcción
/// (`markdownInlinePattern`) y qué se lee de cada una (`markdownInlineText`)
/// son los mismos que usa `RenderedMarkdown` para mostrarla: lo que viaja al
/// chat es lo que se ve en la pantalla, menos las llamadas a notas al pie.
library;

import 'package:sinapsis/core/util/markdown_inline.dart';

/// Una llamada a una nota al pie como las escribe Wikipedia: `[1]`, `[12]`,
/// `[a]`, `[n. 1]`, `[nota 3]`, `[cita requerida]`.
///
/// En una página web es un enlace a la nota —`[[1]](#cite_note-1)`, que el
/// lector muestra como «[1]»— y en un texto copiado, los corchetes sueltos.
/// En lo que se lee para el chat **se van**: no dicen nada sin la nota, que no
/// viaja, y en un párrafo de Wikipedia hay una cada pocas oraciones. Son ruido
/// para el modelo y letras de menos en el tope del pasaje.
final markdownFootnoteCall = RegExp(
  r'\[(?:\d{1,4}|[a-z]|(?:nota|n\.)[ \u00a0]?\d{1,4}|cita requerida)\]',
  caseSensitive: false,
);

/// Los bloques de [text] entre [start] y [end] como se leen, en orden: cada
/// uno en un renglón, sin marcas y con los espacios de más juntados en uno.
///
/// - **lo en línea**, como lo muestra el lector: un enlace es su texto, una
///   imagen su texto alternativo —nada si no tiene, sin dejar un espacio
///   doble—, `[[Título]]` el título, el código y el énfasis lo de adentro, y
///   el HTML en línea (`<a>`, `<img>`, `<sup>`, `<sub>`) su texto;
/// - **sin llamadas a notas al pie** ([markdownFootnoteCall]), salvo adentro
///   del código, que es literal;
/// - **un párrafo** —sus renglones seguidos, hasta un renglón en blanco— es un
///   bloque, con sus renglones unidos por un espacio;
/// - **un título**, **un elemento de una lista** y **una fila de una tabla**
///   son un bloque cada uno: sin `#` ni viñeta —el número de una lista
///   numerada queda, es parte de lo que se lee—, y las celdas de una fila
///   separadas por una coma, como las lee la voz;
/// - **una cita**, sin sus `>`;
/// - **un separador** (`---`) y la fila que separa el encabezado de una tabla,
///   nada;
/// - **un bloque de código** entre cercas (```` ``` ```` o `~~~`) es un bloque,
///   tal cual y sin las cercas.
///
/// Un bloque que no tiene nada que leer —un renglón con una foto sin texto
/// alternativo— no está. Se lee de a un renglón y recién cuando se pide el
/// bloque siguiente: quien solo quiere el comienzo de un capítulo largo no
/// recorre el libro entero.
///
/// Con [keepLineBreaks], los renglones de un párrafo quedan en renglones
/// aparte en vez de unirse con un espacio: lo que se lee es lo mismo, pero se
/// sigue viendo dónde terminaba cada renglón. Lo pide el índice de búsqueda
/// (F46, paso 5i), que une las palabras cortadas con guion al final de un
/// renglón (F22): `ex-⏎plicaciones` unido con un espacio ya no se reconoce.
Iterable<String> markdownPlainBlocks(
  String text, {
  int start = 0,
  int? end,
  bool keepLineBreaks = false,
}) sync* {
  final stop = (end ?? text.length).clamp(0, text.length);
  final paragraph = <String>[];
  final code = <String>[];
  String? fence;

  String? flushParagraph() {
    final block = paragraph
        .where((line) => line.isNotEmpty)
        .join(keepLineBreaks ? '\n' : ' ');
    paragraph.clear();
    return block.isEmpty ? null : block;
  }

  var lineStart = start.clamp(0, stop);
  while (lineStart < stop) {
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1 || lineEnd > stop) lineEnd = stop;
    var line = text.substring(lineStart, lineEnd);
    lineStart = lineEnd + 1;
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

    final openFence = fence;
    if (openFence != null) {
      if (_closesFence(line, openFence)) {
        fence = null;
        final block = code.join('\n').trim();
        code.clear();
        if (block.isNotEmpty) yield block;
      } else {
        code.add(line);
      }
      continue;
    }

    if (_fenceStart.firstMatch(line) case final opening?) {
      if (flushParagraph() case final block?) yield block;
      fence = opening[1];
      continue;
    }

    // Una cita es lo que dice: sin sus `>`, lo de adentro se lee igual.
    final quote = _quotePrefix.firstMatch(line);
    if (quote != null) line = line.substring(quote.end);

    final trimmed = line.trim();
    if (trimmed.isEmpty || _rule.hasMatch(trimmed)) {
      if (flushParagraph() case final block?) yield block;
      continue;
    }

    if (_heading.firstMatch(line) case final heading?) {
      if (flushParagraph() case final block?) yield block;
      final title = _inlinePlain(line.substring(heading.end));
      if (title.isNotEmpty) yield title;
      continue;
    }

    if (trimmed.startsWith('|')) {
      if (flushParagraph() case final block?) yield block;
      if (_tableDelimiter.hasMatch(trimmed)) continue;
      final row = trimmed
          .split('|')
          .map(_inlinePlain)
          .where((cell) => cell.isNotEmpty)
          .join(', ');
      if (row.isNotEmpty) yield row;
      continue;
    }

    if (_bullet.firstMatch(line) case final bullet?) {
      // Un elemento empieza un bloque; los renglones que lo siguen sin
      // marca son suyos, como en Markdown.
      if (flushParagraph() case final block?) yield block;
      paragraph.add(_inlinePlain(line.substring(bullet.end)));
      continue;
    }

    if (_ordered.firstMatch(line) case final item?) {
      if (flushParagraph() case final block?) yield block;
      paragraph.add(_inlinePlain('${item[1]} ${line.substring(item.end)}'));
      continue;
    }

    paragraph.add(_inlinePlain(line));
  }

  if (fence != null) {
    // Una cerca que no se cerró: lo de adentro se lee igual.
    final block = code.join('\n').trim();
    if (block.isNotEmpty) yield block;
  }
  if (flushParagraph() case final block?) yield block;
}

/// [markdown] como se lee ([markdownPlainBlocks]): un bloque por renglón —y,
/// con [keepLineBreaks], cada renglón de un párrafo en el suyo—.
String markdownPlainText(String markdown, {bool keepLineBreaks = false}) =>
    markdownPlainBlocks(markdown, keepLineBreaks: keepLineBreaks).join('\n');

/// [text] entre [start] y [end] como se lee, en un solo renglón y con
/// [maxChars] letras **legibles** como mucho —las de lo que se lee, no las de
/// las direcciones—, cortado en una palabra entera y con «…» si sigue: el
/// pasaje de un documento que viaja al chat (F46, paso 5e). Vacío si el tramo
/// no cae en el texto o no tiene nada que leer.
///
/// - Con [markdown], el tramo se lee con [markdownPlainBlocks] y cada bloque
///   es una oración: uno que no termina en un signo —un título, un elemento
///   de una lista— recibe un punto, y «Siglo XX» seguido de su primer párrafo
///   se lee «Siglo XX. En 1905…», no «Siglo XX En 1905».
/// - Sin él —un PDF, una transcripción—, el texto va tal cual, con los
///   espacios y los renglones juntados en uno: ahí un renglón que termina sin
///   punto es casi siempre una oración que sigue en el renglón de abajo, y un
///   punto la partiría.
String readablePassage(
  String text, {
  required bool markdown,
  required int maxChars,
  int start = 0,
  int? end,
}) {
  if (start < 0 || start >= text.length) return '';
  final stop = (end ?? text.length).clamp(start, text.length);
  final blocks = markdown
      ? markdownPlainBlocks(text, start: start, end: stop).map(_asSentence)
      : _lines(text, start, stop);

  final buffer = StringBuffer();
  for (final block in blocks) {
    if (block.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(block);
    // Lo que sigue ya no entra: no hace falta leerlo.
    if (buffer.length > maxChars) break;
  }
  final piece = buffer.toString().replaceAll(_spaces, ' ').trim();
  if (piece.length <= maxChars) return piece;
  final cut = piece.substring(0, maxChars);
  // Se corta en la última palabra entera, si hay una cerca.
  final space = cut.lastIndexOf(' ');
  final kept = space > maxChars * 0.8 ? cut.substring(0, space) : cut;
  return '${kept.trimRight()}…';
}

/// Los renglones de [text] entre [start] y [stop], de a uno y con los
/// espacios juntados: un texto que no es Markdown, tal cual.
Iterable<String> _lines(String text, int start, int stop) sync* {
  var lineStart = start;
  while (lineStart < stop) {
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1 || lineEnd > stop) lineEnd = stop;
    yield text.substring(lineStart, lineEnd).replaceAll(_spaces, ' ').trim();
    lineStart = lineEnd + 1;
  }
}

/// [block] como una oración: con un punto si no termina en un signo que ya
/// la cierre (ni en uno de esos seguido de comillas o de un paréntesis).
String _asSentence(String block) =>
    _sentenceEnd.hasMatch(block) ? block : '$block.';

/// Lo que se lee de [line], un renglón: ver [markdownPlainBlocks].
String _inlinePlain(String line) {
  final out = StringBuffer();
  _readInline(line, 0, line.length, out);
  return out.toString().replaceAll(_spaces, ' ').trim();
}

/// Lee [text] entre [start] y [end] —un renglón, o lo de adentro de una
/// construcción que se vuelve a leer— y escribe en [out] lo que se lee.
void _readInline(String text, int start, int end, StringBuffer out) {
  final body = text.substring(start, end);
  var cursor = 0;
  for (final match in markdownInlinePattern.allMatches(body)) {
    out.write(_withoutFootnotes(body.substring(cursor, match.start)));
    final read = markdownInlineText(match);
    if (read.kind.nested) {
      _readInline(body, read.start, read.end, out);
    } else if (read.kind == MarkdownInline.code) {
      // El código es literal: un `[1]` adentro es código, no una nota.
      out.write(body.substring(read.start, read.end));
    } else {
      out.write(_withoutFootnotes(body.substring(read.start, read.end)));
    }
    cursor = match.end;
  }
  out.write(_withoutFootnotes(body.substring(cursor)));
}

String _withoutFootnotes(String text) =>
    text.replaceAll(markdownFootnoteCall, '');

/// Si una cerca de código abierta con [fence] se cierra en [line]: la misma
/// marca, al menos igual de larga, y nada más.
bool _closesFence(String line, String fence) {
  final trimmed = line.trim();
  return trimmed.length >= fence.length &&
      trimmed.startsWith(fence) &&
      trimmed.split('').every((char) => char == fence[0]);
}

final _fenceStart = RegExp('^ {0,3}(`{3,}|~{3,})');
final _quotePrefix = RegExp(r'^[ \t]*(?:>[ \t]?)+');
// Las mismas marcas que entiende el lector, más las que él no necesita: el
// `+` de una viñeta, la sangría de una lista anidada y la lista numerada.
final _heading = RegExp(r'^ {0,3}#{1,6}[ \t]+');
final _rule = RegExp(r'^(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$');
final _bullet = RegExp(r'^[ \t]*[-*+][ \t]+');
final _ordered = RegExp(r'^[ \t]*(\d{1,9}[.)])[ \t]+');
final _tableDelimiter = RegExp(
  r'^\|?(?:[ \t]*:?-+:?[ \t]*\|)+(?:[ \t]*:?-+:?[ \t]*)?$',
);
final _spaces = RegExp(r'\s+');
final _sentenceEnd = RegExp('[.!?…:;][)\\]»"\'”’]*\$');
