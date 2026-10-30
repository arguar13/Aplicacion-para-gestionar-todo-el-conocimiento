import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/util/word_folding.dart';
import 'package:sinapsis/features/export/data/marked/mark_locator.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';

/// Un pedazo de un texto de la página, con lo que lo pinta (F38): el fondo y
/// la línea de debajo, cada uno con su tramo, o ninguno; y las notas en el
/// texto (F45, mejora 19) cuyo pedazo termina con él —sus ids, los de
/// [MarkPainter.placeNotes]—: su llamada va justo después.
typedef MarkedPiece = ({
  String text,
  DocumentMark? fill,
  DocumentMark? underline,
  List<int> notes,
});

/// Lo que no se recorre buscando texto en un HTML o un XHTML: no es texto que
/// se lea, o no admite un `<mark>` adentro. Es la misma lista con que
/// `showableArchivedPage` (F36) busca las oraciones en la página.
const markOpaqueElements = {
  'script',
  'style',
  'noscript',
  'template',
  'textarea',
  'select',
  'option',
  'title',
  'svg',
  'math',
};

/// Ubica tramos de [DocumentMark] en los textos de una página o un capítulo
/// y dice qué letras pinta cada uno (F38).
///
/// Lo comparten `HtmlMarkWriter` y `EpubMarkWriter`, que solo se diferencian
/// en cómo recorren el árbol y cómo escriben el resultado.
///
/// Los textos se unen en uno solo —con un salto de línea entre uno y otro— y
/// los tramos se ubican ahí con [locateMarks] (letras y números, sin
/// mayúsculas ni acentos; con las direcciones del Markdown de lado), como en
/// los demás formatos; después, cada lugar encontrado se reparte entre los
/// textos que cruza. Cuando se pisan dos tramos, queda el que viene después
/// en la lista (el que tiene la prioridad mayor). Un fondo y una línea sí
/// pueden convivir en la misma letra.
///
/// Las notas en el texto (F45, mejora 19) se ubican igual, pero no pintan:
/// se anota dónde termina su pedazo, que es donde va su llamada.
class MarkPainter {
  MarkPainter(this.texts, this.extracted) {
    final buffer = StringBuffer();
    for (final text in texts) {
      _starts.add(buffer.length);
      buffer
        ..write(text)
        ..write('\n');
    }
    _haystack = buffer.toString();
  }

  /// Los textos de la página, en orden de lectura.
  final List<String> texts;

  /// El texto extraído, en cuyas posiciones están los tramos.
  final String extracted;

  late final String _haystack;

  /// Dónde empieza cada texto en [_haystack].
  final _starts = <int>[];

  /// Por texto, de cada letra: la prioridad de quien la pinta de fondo y de
  /// quien la subraya (-1, nadie).
  final _fills = <int, List<int>>{};
  final _underlines = <int, List<int>>{};

  /// Los tramos puestos, por prioridad.
  final _marks = <int, DocumentMark>{};

  /// Por texto, dónde van las llamadas de las notas: la posición en el texto
  /// —justo después de la última letra del pedazo— y los ids de las que van
  /// ahí.
  final _noteCalls = <int, Map<int, List<int>>>{};

  /// Los textos en que se pintó algo o va la llamada de una nota.
  Iterable<int> get touched => {
    ..._fills.keys,
    ..._underlines.keys,
    ..._noteCalls.keys,
  };

  /// Si no se ubicó ningún tramo ni ninguna nota.
  bool get isEmpty => _marks.isEmpty && _noteCalls.isEmpty;

  /// Los ids de las notas que se ubicaron, en el orden de la página: el de
  /// sus números.
  List<int> get noteOrder => [
    for (final node in _noteCalls.keys.toList()..sort())
      for (final offset in _noteCalls[node]!.keys.toList()..sort())
        ..._noteCalls[node]![offset]!,
  ];

  /// Ubica el pedazo de cada una de [notes] y anota dónde va su llamada, con
  /// el id que le da [ids] —su lugar en la lista original—, o su lugar en
  /// [notes]. Devuelve, por nota, si se encontró.
  List<bool> placeNotes(List<DocumentNote> notes, {List<int>? ids}) {
    final spans = locateMarks(
      haystack: _haystack,
      extracted: extracted,
      marks: [
        for (final note in notes)
          DocumentMark(
            start: note.start,
            end: note.end,
            excerpt: note.excerpt,
            color: note.color,
          ),
      ],
      markdownUrls: true,
    );
    return [
      for (var i = 0; i < notes.length; i++)
        if (spans[i] case final span?)
          _placeCall(span.end, ids?[i] ?? i)
        else
          false,
    ];
  }

  bool _placeCall(int end, int id) {
    final node = _nodeAt(end - 1);
    // Si el pedazo termina en el salto que separa un texto del siguiente, la
    // llamada va al final del texto.
    final length = texts[node].length;
    final offset = end - _starts[node] > length ? length : end - _starts[node];
    ((_noteCalls[node] ??= {})[offset] ??= []).add(id);
    return true;
  }

  /// Ubica y pinta [marks]; devuelve, por tramo, si se encontró. La prioridad
  /// de cada uno es la que da [priorities] —su lugar en la lista original—, o
  /// su lugar en [marks].
  List<bool> paint(List<DocumentMark> marks, {List<int>? priorities}) {
    final spans = locateMarks(
      haystack: _haystack,
      extracted: extracted,
      marks: marks,
      markdownUrls: true,
    );
    return [
      for (var i = 0; i < marks.length; i++)
        spans[i] != null && _paint(marks[i], priorities?[i] ?? i, spans[i]!),
    ];
  }

  bool _paint(DocumentMark mark, int priority, MarkSpan span) {
    final first = _nodeAt(span.start);
    final last = _nodeAt(span.end - 1);
    // Si el tramo termina en un signo —el punto de una oración—, el signo
    // pegado a la última letra va con él; si termina en una letra, no: la
    // coma que sigue a una palabra marcada no es de la palabra.
    final tail = mark.excerpt.isEmpty
        ? null
        : mark.excerpt.codeUnitAt(mark.excerpt.length - 1);
    final withClosing =
        tail != null && !_isSpace(tail) && foldWordChar(tail) == null;

    _marks[priority] = mark;
    final target = mark.style == HighlightStyle.fill ? _fills : _underlines;
    for (var n = first; n <= last; n++) {
      final data = texts[n];
      final from = n == first ? span.start - _starts[n] : 0;
      var to = n == last ? span.end - _starts[n] : data.length;
      if (n == last && withClosing) {
        while (to < data.length &&
            !_isSpace(data.codeUnitAt(to)) &&
            foldWordChar(data.codeUnitAt(to)) == null) {
          to++;
        }
      }
      final slots = target[n] ??= List<int>.filled(data.length, -1);
      for (var i = from; i < to; i++) {
        if (slots[i] < priority) slots[i] = priority;
      }
    }
    return true;
  }

  /// El texto que tiene el lugar [offset] de [_haystack].
  int _nodeAt(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_starts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// El texto [node] cortado en pedazos según lo que lo pinta y dónde van
  /// las llamadas de las notas, o `null` si no lleva nada o es solo espacios
  /// —entre las filas de una tabla o los ítems de una lista, un `<mark>`
  /// movería cosas de lugar—.
  List<MarkedPiece>? piecesOf(int node) {
    final fills = _fills[node];
    final underlines = _underlines[node];
    final calls = _noteCalls[node] ?? const <int, List<int>>{};
    if (fills == null && underlines == null && calls.isEmpty) return null;
    final data = texts[node];
    if (data.trim().isEmpty) return null;
    int fillAt(int i) => fills?[i] ?? -1;
    int lineAt(int i) => underlines?[i] ?? -1;

    final pieces = <MarkedPiece>[];
    var start = 0;
    while (start < data.length) {
      final fill = fillAt(start);
      final line = lineAt(start);
      var end = start + 1;
      while (end < data.length &&
          !calls.containsKey(end) &&
          fillAt(end) == fill &&
          lineAt(end) == line) {
        end++;
      }
      pieces.add((
        text: data.substring(start, end),
        fill: _marks[fill],
        underline: _marks[line],
        notes: calls[end] ?? const <int>[],
      ));
      start = end;
    }
    return pieces;
  }
}

/// El `style` del `<mark>` de [piece]: el fondo con su color, o la línea de
/// debajo con el suyo, o las dos cosas.
///
/// Un `<mark>` trae de fábrica el fondo amarillo del navegador; el subrayado
/// lo apaga, porque es una línea y no un fondo.
String markStyleOf(MarkedPiece piece) {
  final fill = piece.fill;
  final underline = piece.underline;
  final parts = <String>[];
  if (fill == null) {
    parts.add('background-color:transparent;color:inherit');
  } else {
    parts.add('background-color:${markHex(fill.color)}');
  }
  if (underline != null) {
    parts
      ..add('text-decoration:underline')
      ..add('text-decoration-color:${markHex(underline.color)}');
  }
  return parts.join(';');
}

/// La nota de [piece] para su `title`, si el tramo que la pinta tiene una.
String? markNoteOf(MarkedPiece piece) {
  for (final mark in [piece.fill, piece.underline]) {
    final note = mark?.note;
    if (note != null && note.trim().isNotEmpty) return note;
  }
  return null;
}

/// [argb] como `#RRGGBB`: el navegador no necesita el alfa.
String markHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

bool _isSpace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;
