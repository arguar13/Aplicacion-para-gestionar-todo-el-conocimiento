import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/mark_locator.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';

/// Marca tramos en un Markdown y devuelve el mismo Markdown (F38): `==así==`
/// alrededor de cada tramo de fondo, y `<u>así</u>` alrededor de cada uno
/// subrayado.
///
/// Markdown no tiene colores: un tramo marcado de verde y uno de rosa salen
/// igual. Tampoco tiene comentarios: la nota de un resaltado no se escribe.
///
/// **Las notas en el texto** (F45, mejora 19) son notas al pie, como las
/// escriben GitHub, Obsidian y Pandoc: la llamada `[^nota-1]` justo después
/// del pedazo citado y, al final del archivo, `[^nota-1]: lo que dice`, en el
/// orden del texto. Una llamada nunca cae adentro de la sintaxis: si el pedazo
/// termina en la dirección de un enlace, en un código o en una etiqueta, va
/// después; si termina en un bloque de código, en un renglón propio después
/// del bloque.
///
/// **Sin romper la sintaxis.** Las marcas van **por renglón**: un tramo que
/// cruza un salto de línea o de párrafo se parte en uno por renglón, porque
/// un `==` abierto en un párrafo y cerrado en otro no lo lee ningún
/// programa. Dentro de un renglón:
///
/// - **No se marca el comienzo del bloque**: el `#` de un encabezado, el
///   `-` o el `3.` de una lista, el `>` de una cita, el `- [ ]` de una tarea.
///   Un `==3. Los pasos==` al principio del renglón dejaría de ser una
///   lista.
/// - **Un tramo que cruza otra marca** —una negrita, una cursiva, un
///   tachado, un enlace, un código— se envuelve entero si esa marca queda
///   toda adentro o toda afuera (`==dijo **esto** y aquello==`). Si el
///   tramo corta una por la mitad (`==esto** y aquello==`), se parte
///   alrededor de las marcas y se envuelve solo el texto de entre ellas.
/// - **Nunca se marca** lo que es sintaxis y no texto: la dirección de un
///   enlace, una etiqueta HTML, el interior de un código, un bloque de código
///   con ``` o ~~~, el encabezado `---` del principio. Un tramo ahí se
///   saltea.
/// - En una **fila de tabla**, la barra `|` también parte el tramo: un
///   resaltado no puede cruzar de una celda a otra.
///
/// Un tramo que no se encuentra se saltea. Si dos se pisan, gana el que
/// viene después en la lista.
class MarkdownMarkWriter {
  const MarkdownMarkWriter();

  /// El Markdown [markdown] con [marks] marcados y [notes] como notas al pie.
  /// [text] es el texto extraído al que se refieren las posiciones de los
  /// dos; para un Markdown es el mismo [markdown], y los tramos se ubican sin
  /// buscar.
  String write({
    required String markdown,
    required String text,
    required List<DocumentMark> marks,
    List<DocumentNote> notes = const [],
  }) {
    if (marks.isEmpty && notes.isEmpty) return markdown;
    final protected = _protectedRanges(markdown);
    final inserts = <_Insert>[];
    if (marks.isNotEmpty) {
      _markInserts(markdown, text, marks, protected, inserts);
    }
    final definitions = notes.isEmpty
        ? const <String>[]
        : _noteInserts(markdown, text, notes, protected, inserts);
    if (inserts.isEmpty) return markdown;

    // Se arma de corrido, en una sola pasada. En un mismo lugar,
    // lo que cierra va antes de lo que abre.
    inserts.sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.order.compareTo(b.order);
    });
    final out = StringBuffer();
    var from = 0;
    for (final insert in inserts) {
      out
        ..write(markdown.substring(from, insert.position))
        ..write(insert.text);
      from = insert.position;
    }
    out.write(markdown.substring(from));
    if (definitions.isNotEmpty) {
      // Las notas al pie, al final: separadas de lo último por un renglón en
      // blanco, como un bloque más.
      final body = out.toString().trimRight();
      return '$body\n\n${definitions.join('\n')}\n';
    }
    return out.toString();
  }
}

/// Pinta [marks]: un tramo por letra —gana el último— y cada tramo,
/// envuelto por renglón (ver [_wrapRange]).
void _markInserts(
  String markdown,
  String text,
  List<DocumentMark> marks,
  List<({int start, int end})> protected,
  List<_Insert> inserts,
) {
  final spans = locateMarks(haystack: markdown, extracted: text, marks: marks);

  final paint = Int32List(markdown.length)..fillRange(0, markdown.length, -1);
  var found = false;
  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    if (span == null) continue;
    paint.fillRange(span.start, span.end, i);
    found = true;
  }
  if (!found) return;

  var at = 0;
  while (at < markdown.length) {
    final mark = paint[at];
    if (mark < 0) {
      at++;
      continue;
    }
    var end = at + 1;
    while (end < markdown.length && paint[end] == mark) {
      end++;
    }
    _wrapRange(markdown, at, end, marks[mark], protected, inserts);
    at = end;
  }
}

/// Las llamadas de [notes] después de su pedazo, y sus definiciones, en el
/// orden del texto. Las etiquetas no pisan las notas al pie que el archivo ya
/// tuviera.
List<String> _noteInserts(
  String markdown,
  String text,
  List<DocumentNote> notes,
  List<({int start, int end})> protected,
  List<_Insert> inserts,
) {
  final spans = locateMarks(
    haystack: markdown,
    extracted: text,
    marks: [
      for (final note in notes)
        DocumentMark(
          start: note.start,
          end: note.end,
          excerpt: note.excerpt,
          color: note.color,
        ),
    ],
  );
  final found = [
    for (var i = 0; i < notes.length; i++)
      if (spans[i] case final span?) (note: notes[i], end: span.end),
  ]..sort((a, b) => a.end.compareTo(b.end));

  var label = 'nota';
  while (markdown.contains('[^$label-')) {
    label = 'sinapsis-$label';
  }
  final definitions = <String>[];
  for (var i = 0; i < found.length; i++) {
    final name = '[^$label-${i + 1}]';
    final (:position, :ownLine) = _notePlace(markdown, found[i].end, protected);
    inserts.add(
      _Insert(position, ownLine ? '$name\n\n' : name, _Insert.reference),
    );
    final lines = found[i].note.note.trim().split(RegExp(r'\r\n|\r|\n'));
    definitions.add(
      [
        '$name: ${lines.first}',
        // Los renglones que siguen, con sangría: siguen siendo de la nota.
        for (final line in lines.skip(1))
          if (line.isEmpty) '' else '    $line',
      ].join('\n'),
    );
  }
  return definitions;
}

/// Dónde va la llamada de una nota cuyo pedazo termina en [end]: ahí, salvo
/// que caiga adentro de la sintaxis. En un bloque de código o en el
/// encabezado del principio, al empezar el renglón que les sigue, en uno
/// propio (`ownLine`); en la dirección de un enlace, un código o una
/// etiqueta, apenas terminan.
({int position, bool ownLine}) _notePlace(
  String markdown,
  int end,
  List<({int start, int end})> protected,
) {
  for (final range in protected) {
    if (end > range.start && end < range.end) {
      return (position: range.end, ownLine: true);
    }
  }
  final lineBegin = end == 0 ? 0 : markdown.lastIndexOf('\n', end - 1) + 1;
  var lineEnd = markdown.indexOf('\n', lineBegin);
  if (lineEnd < 0) lineEnd = markdown.length;
  final line = markdown.substring(lineBegin, lineEnd);
  var at = end - lineBegin;
  for (final literal in _scan(line).literals) {
    if (at > literal.start && at < literal.end) {
      at = literal.end;
      // El cierre de un código: sus comillas invertidas van con él.
      while (at < line.length && line[at] == '`') {
        at++;
      }
    }
  }
  return (position: lineBegin + at, ownLine: false);
}

class _Insert {
  _Insert(this.position, this.text, this.order);

  /// Lo que cierra un tramo, la llamada de una nota y lo que abre otro: en
  /// un mismo lugar, en ese orden —la llamada es del pedazo que termina ahí,
  /// no del que empieza—.
  static const closing = 0;
  static const reference = 1;
  static const opening = 2;

  final int position;
  final String text;

  /// [closing], [reference] u [opening].
  final int order;
}

/// Lo que va antes y después de un tramo, según su estilo.
(String, String) _delimiters(HighlightStyle style) => switch (style) {
  HighlightStyle.fill => ('==', '=='),
  HighlightStyle.underline => ('<u>', '</u>'),
};

/// El comienzo de un bloque en un renglón: encabezado, cita, lista (con su
/// casilla) o numeración.
final _blockPrefix = RegExp(
  r'^(?:\s{0,3}(?:#{1,6}[ \t]+|>[ \t]?|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d{1,9}[.)][ \t]+))+',
);

void _wrapRange(
  String s,
  int from,
  int to,
  DocumentMark mark,
  List<({int start, int end})> protected,
  List<_Insert> inserts,
) {
  final (open, close) = _delimiters(mark.style);
  var lineStart = from;
  while (lineStart < to) {
    // El renglón que contiene este trozo, completo, para ver su sintaxis.
    final lineBegin = lineStart == 0
        ? 0
        : s.lastIndexOf('\n', lineStart - 1) + 1;
    var lineEnd = s.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = s.length;
    final pieceEnd = lineEnd < to ? lineEnd : to;
    final next = lineEnd + 1;

    var line = s.substring(lineBegin, lineEnd);
    // Un fin de línea de Windows no es parte del renglón.
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

    var begin = lineStart;
    final prefix = _blockPrefix.firstMatch(line);
    if (prefix != null && begin < lineBegin + prefix.end) {
      begin = lineBegin + prefix.end;
    }
    final limit = pieceEnd < lineBegin + line.length
        ? pieceEnd
        : lineBegin + line.length;

    if (begin < limit && !_isProtected(protected, lineBegin)) {
      final isTableRow = line.trimLeft().startsWith('|');
      for (final piece in _safePieces(
        line,
        begin - lineBegin,
        limit - lineBegin,
        isTableRow,
      )) {
        inserts
          ..add(_Insert(lineBegin + piece.start, open, _Insert.opening))
          ..add(_Insert(lineBegin + piece.end, close, _Insert.closing));
      }
    }
    lineStart = next;
  }
}

bool _isProtected(List<({int start, int end})> ranges, int position) {
  for (final range in ranges) {
    if (position >= range.start && position < range.end) return true;
  }
  return false;
}

/// Los bloques de código con ``` o ~~~ y el encabezado `---` de un
/// Markdown que lo trae al principio: ahí un `==` se leería literal.
List<({int start, int end})> _protectedRanges(String s) {
  final ranges = <({int start, int end})>[];
  var offset = 0;
  String? fence;
  int? fenceStart;
  var first = true;
  var inFrontMatter = false;
  var frontMatterStart = 0;

  for (final line in s.split('\n')) {
    final trimmed = line.trim();
    final lineEnd = offset + line.length + 1;
    if (first && trimmed == '---') {
      inFrontMatter = true;
      frontMatterStart = offset;
    } else if (inFrontMatter) {
      if (trimmed == '---' || trimmed == '...') {
        ranges.add((start: frontMatterStart, end: lineEnd));
        inFrontMatter = false;
      }
    } else if (fence == null) {
      final open = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
      if (open != null) {
        fence = open.group(1);
        fenceStart = offset;
      }
    } else {
      final fenceChar = fence[0];
      final close = RegExp(
        '^\\s{0,3}($fenceChar{${fence.length},})\\s*\$',
      ).hasMatch(line);
      if (close) {
        ranges.add((start: fenceStart!, end: lineEnd));
        fence = null;
      }
    }
    first = false;
    offset = lineEnd;
  }
  // Un bloque de código que nunca se cierra llega hasta el final. Un `---`
  // del principio que nunca se cierra era una línea horizontal, no un
  // encabezado, y no protege nada.
  if (fence != null) ranges.add((start: fenceStart!, end: s.length));
  return ranges;
}

// ---------------------------------------------------------------------
// La sintaxis de un renglón
// ---------------------------------------------------------------------

/// Un delimitador de énfasis, de código, de tachado o de enlace.
class _Token {
  _Token(this.position, this.length, this.kind);

  final int position;
  final int length;

  /// `**`, `__`, `~~`, `*`, `_`, `` ` ``, `[` o `]`.
  final String kind;

  int get end => position + length;
}

class _LineSyntax {
  final tokens = <_Token>[];

  /// Lo que es sintaxis y no texto: la dirección de un enlace, una
  /// etiqueta HTML, el interior de un código.
  final literals = <({int start, int end})>[];

  bool isLiteral(int index) {
    for (final range in literals) {
      if (index >= range.start && index < range.end) return true;
    }
    return false;
  }
}

bool _isAlnum(String ch) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);

_LineSyntax _scan(String line) {
  final syntax = _LineSyntax();
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch == r'\' && i + 1 < line.length) {
      // Un carácter escapado es texto.
      i += 2;
    } else if (ch == '`') {
      // Un código: del primer ` al que lo cierra, con el mismo largo.
      var run = 1;
      while (i + run < line.length && line[i + run] == '`') {
        run++;
      }
      final fence = '`' * run;
      final close = line.indexOf(fence, i + run);
      syntax.tokens.add(_Token(i, run, '`'));
      if (close < 0) {
        i += run;
      } else {
        syntax.literals.add((start: i + run, end: close));
        syntax.tokens.add(_Token(close, run, '`'));
        i = close + run;
      }
    } else if (ch == '<' &&
        i + 1 < line.length &&
        RegExp('[A-Za-z/!]').hasMatch(line[i + 1])) {
      final close = line.indexOf('>', i);
      if (close < 0) {
        i++;
      } else {
        syntax.literals.add((start: i, end: close + 1));
        i = close + 1;
      }
    } else if (ch == '*' || ch == '_' || ch == '~') {
      var run = 1;
      while (i + run < line.length && line[i + run] == ch) {
        run++;
      }
      final before = i > 0 ? line[i - 1] : ' ';
      final after = i + run < line.length ? line[i + run] : ' ';
      final isDelimiter = switch (ch) {
        // Un `_` entre letras (`un_nombre`) es texto; un `*` o un `~`
        // suelto entre espacios (`2 * 3`) también.
        '_' => !(_isAlnum(before) && _isAlnum(after)),
        '~' => run >= 2,
        _ => !(before.trim().isEmpty && after.trim().isEmpty),
      };
      if (isDelimiter) {
        // De a dos, como las abre Markdown: `***` es `**` más `*`.
        var left = run;
        var p = i;
        while (left > 0) {
          final size = left >= 2 ? 2 : 1;
          if (ch == '~' && size == 1) break;
          syntax.tokens.add(_Token(p, size, ch * size));
          p += size;
          left -= size;
        }
      }
      i += run;
    } else if (ch == '[') {
      syntax.tokens.add(_Token(i, 1, '['));
      i++;
    } else if (ch == ']') {
      syntax.tokens.add(_Token(i, 1, ']'));
      // La dirección del enlace: `](...)`.
      if (i + 1 < line.length && line[i + 1] == '(') {
        final close = line.indexOf(')', i + 2);
        if (close > 0) {
          syntax.literals.add((start: i + 1, end: close + 1));
          i = close + 1;
          continue;
        }
      }
      i++;
    } else {
      i++;
    }
  }
  return syntax;
}

/// Los pedazos de [from]..[to] de [line] donde se puede escribir `==` sin
/// romper nada: el tramo entero si cae parejo, o los textos de entre las
/// marcas si corta alguna por la mitad.
List<({int start, int end})> _safePieces(
  String line,
  int from,
  int to,
  bool isTableRow,
) {
  final syntax = _scan(line);
  // Un tramo que empieza adentro de la sintaxis no se marca.
  if (syntax.isLiteral(from)) return const [];

  final whole = _trim(line, from, to);
  if (whole == null) return const [];

  if (_isBalanced(syntax, line, whole.start, whole.end, isTableRow)) {
    return [whole];
  }

  // Se parte alrededor de cada delimitador, dirección o etiqueta.
  final pieces = <({int start, int end})>[];
  var pieceStart = whole.start;
  void flush(int end) {
    final trimmed = _trim(line, pieceStart, end);
    if (trimmed != null) pieces.add(trimmed);
  }

  var i = whole.start;
  while (i < whole.end) {
    final token = syntax.tokens
        .where((t) => t.position == i && t.end <= whole.end)
        .firstOrNull;
    final literal = syntax.literals
        .where((l) => l.start <= i && i < l.end)
        .firstOrNull;
    if (token != null) {
      flush(i);
      i = token.end;
      pieceStart = i;
    } else if (literal != null) {
      flush(i);
      i = literal.end;
      pieceStart = i;
    } else if (isTableRow && line[i] == '|') {
      flush(i);
      i++;
      pieceStart = i;
    } else {
      i++;
    }
  }
  flush(whole.end);
  return pieces;
}

/// [from]..[to] sin espacios en los bordes, o `null` si no queda ninguna
/// letra ni número.
({int start, int end})? _trim(String line, int from, int to) {
  var start = from;
  var end = to;
  while (start < end && line[start].trim().isEmpty) {
    start++;
  }
  while (end > start && line[end - 1].trim().isEmpty) {
    end--;
  }
  if (start >= end) return null;
  for (var i = start; i < end; i++) {
    if (_isAlnum(line[i])) return (start: start, end: end);
  }
  return null;
}

/// Si el tramo [from]..[to] tiene toda su sintaxis adentro: cada
/// delimitador que abre adentro cierra adentro, y ninguno de los que se
/// abrieron antes se cierra acá; sin cortar ninguno por la mitad.
bool _isBalanced(
  _LineSyntax syntax,
  String line,
  int from,
  int to,
  bool isTableRow,
) {
  // Un literal —una etiqueta, una dirección, un código— cortado al final. Al
  // principio no puede estar cortado: `_safePieces` ya descartó un tramo que
  // empieza adentro de uno. Y ningún delimitador queda partido por un borde,
  // porque los bordes del tramo son letras o números y los delimitadores no.
  for (final range in syntax.literals) {
    if (range.start < to && to < range.end) return false;
  }
  if (isTableRow && line.substring(from, to).contains('|')) return false;

  final open = <String, bool>{};
  final inside = <String, int>{};
  var depth = 0;
  var minDepth = 0;
  for (final token in syntax.tokens) {
    if (token.position < from) {
      if (token.kind != '[' && token.kind != ']') {
        open[token.kind] = !(open[token.kind] ?? false);
      }
    } else if (token.end <= to) {
      if (token.kind == '[') {
        depth++;
      } else if (token.kind == ']') {
        depth--;
        if (depth < minDepth) minDepth = depth;
      } else {
        inside[token.kind] = (inside[token.kind] ?? 0) + 1;
      }
    }
  }
  if (depth != 0 || minDepth < 0) return false;
  for (final MapEntry(key: kind, value: count) in inside.entries) {
    final wasOpen = open[kind] ?? false;
    // Si ya estaba abierto, cualquier delimitador de ese tipo lo cierra.
    if (wasOpen && count > 0) return false;
    if (!wasOpen && count.isOdd) return false;
  }
  // Y dentro de un código o de un enlace de antes, solo texto.
  if (open['`'] ?? false) return false;
  return true;
}
