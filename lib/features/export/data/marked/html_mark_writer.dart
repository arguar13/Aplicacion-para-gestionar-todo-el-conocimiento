import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/export/data/marked/mark_painter.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/export/domain/entities/document_note.dart';

/// Escribe resaltados en la página web archivada (F38): el mismo HTML, con
/// cada tramo envuelto en un `<mark>` con su color, que se abre en cualquier
/// navegador sin conexión.
///
/// Un tramo de fondo lleva `background-color:#RRGGBB`; uno subrayado, una
/// línea (`text-decoration:underline` con el `text-decoration-color`) y el
/// fondo apagado; su nota va en el `title`, el globo que sale al pasar el
/// mouse. Todo en el `style` de la propia marca: la página no necesita una
/// hoja de estilos más ni un programa, y la archivada puede traer los suyos.
///
/// Los tramos se ubican en la página con `locateMarks`, como en los demás
/// formatos y como hace lo estudiado de F36: comparando solo letras y números,
/// porque el texto extraído es el artículo en Markdown y la página tiene
/// además su menú y sus etiquetas. Un tramo puede cruzar etiquetas —una
/// negrita, un enlace—: se parte en un `<mark>` por cada texto. Lo que no se
/// encuentra se saltea.
///
/// Las notas en el texto (F45, mejora 19) son notas al pie de la página: la
/// llamada —su número volado, que lleva a la nota— va justo después del
/// pedazo citado, y las notas, numeradas en el orden de la página, al final,
/// cada una con su vuelta a la llamada. Con los roles de accesibilidad de las
/// notas (`doc-noteref`, `doc-endnotes`, `doc-backlink`).
///
/// Lo demás de la página queda como estaba —sus imágenes ya incrustadas, sus
/// hojas de estilo, sus programas—. El HTML se lee y se vuelve a escribir, así
/// que el marcado puede salir normalizado (comillas de los atributos,
/// etiquetas cerradas), pero no cambia nada de lo que se ve ni se lee.
class HtmlMarkWriter {
  const HtmlMarkWriter();

  /// La página [html] con [marks] resaltados y [notes] como notas al pie.
  /// [content] es el texto extraído, en cuyas posiciones están los dos.
  String write(
    String html,
    String content,
    List<DocumentMark> marks, [
    List<DocumentNote> notes = const [],
  ]) {
    if (marks.isEmpty && notes.isEmpty) return html;
    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final texts = <Text>[];
    _collect(root, texts);
    final painter = MarkPainter([for (final text in texts) text.data], content)
      ..paint(marks)
      ..placeNotes(notes);
    if (painter.isEmpty) return html;

    // El número de cada nota, en el orden de la página.
    final order = painter.noteOrder;
    final numbers = {for (var i = 0; i < order.length; i++) order[i]: i + 1};

    for (final node in painter.touched.toList()..sort()) {
      final pieces = painter.piecesOf(node);
      if (pieces == null) continue;
      final text = texts[node];
      final parent = text.parentNode;
      if (parent == null) continue;
      final index = parent.nodes.indexOf(text);
      text.remove();
      parent.nodes.insertAll(index, [
        for (final p in pieces) ...[
          _nodeOf(p),
          for (final id in p.notes) _callOf(numbers[id]!),
        ],
      ]);
    }
    if (order.isNotEmpty) {
      root.append(_footnotes([for (final id in order) notes[id].note]));
    }
    return document.outerHtml;
  }
}

void _collect(Node node, List<Text> texts) {
  for (final child in node.nodes) {
    if (child is Text) {
      texts.add(child);
    } else if (child is Element &&
        !markOpaqueElements.contains(child.localName)) {
      _collect(child, texts);
    }
  }
}

/// La llamada a la nota [number]: su número volado, que lleva a la nota.
Element _callOf(int number) => Element.tag('sup')
  ..append(
    Element.tag('a')
      ..attributes.addAll({
        'href': '#$kNoteIdPrefix$number',
        'id': '$kNoteCallIdPrefix$number',
        'role': 'doc-noteref',
      })
      ..append(Text('$number')),
  );

/// Las notas al pie de la página, en el orden de sus números: lo que dice
/// cada una —un renglón por renglón— y su vuelta a la llamada.
Element _footnotes(List<String> notes) {
  final list = Element.tag('ol');
  for (var i = 0; i < notes.length; i++) {
    final number = i + 1;
    final item = Element.tag('li')..attributes['id'] = '$kNoteIdPrefix$number';
    final lines = notes[i].trim().split(RegExp(r'\r\n|\r|\n'));
    for (var l = 0; l < lines.length; l++) {
      if (l > 0) item.append(Element.tag('br'));
      item.append(Text(lines[l]));
    }
    item
      ..append(Text(' '))
      ..append(
        Element.tag('a')
          ..attributes.addAll({
            'href': '#$kNoteCallIdPrefix$number',
            'role': 'doc-backlink',
          })
          ..append(Text('↩')),
      );
    list.append(item);
  }
  return Element.tag('section')
    ..attributes.addAll({'role': 'doc-endnotes', 'class': 'sinapsis-notas'})
    ..append(Element.tag('hr'))
    ..append(list);
}

/// Lo que antecede al `id` de una nota al pie y al de su llamada, en una
/// página y en un capítulo de un libro: con el nombre de la app, para no
/// chocar con los `id` que ya traen.
const kNoteIdPrefix = 'sinapsis-nota-';
const kNoteCallIdPrefix = 'sinapsis-llamada-';

Node _nodeOf(MarkedPiece piece) {
  if (piece.fill == null && piece.underline == null) return Text(piece.text);
  final mark = Element.tag('mark')
    ..attributes['style'] = markStyleOf(piece)
    ..append(Text(piece.text));
  final note = markNoteOf(piece);
  if (note != null) mark.attributes['title'] = note;
  return mark;
}
