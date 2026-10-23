import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/export/data/marked/mark_painter.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';

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
/// Lo demás de la página queda como estaba —sus imágenes ya incrustadas, sus
/// hojas de estilo, sus programas—. El HTML se lee y se vuelve a escribir, así
/// que el marcado puede salir normalizado (comillas de los atributos,
/// etiquetas cerradas), pero no cambia nada de lo que se ve ni se lee.
class HtmlMarkWriter {
  const HtmlMarkWriter();

  /// La página [html] con [marks] resaltados. [content] es el texto extraído,
  /// en cuyas posiciones están [marks].
  String write(String html, String content, List<DocumentMark> marks) {
    if (marks.isEmpty) return html;
    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final texts = <Text>[];
    _collect(root, texts);
    final painter = MarkPainter([for (final text in texts) text.data], content)
      ..paint(marks);
    if (painter.isEmpty) return html;

    for (final node in painter.touched.toList()..sort()) {
      final pieces = painter.piecesOf(node);
      if (pieces == null) continue;
      final text = texts[node];
      final parent = text.parentNode;
      if (parent == null) continue;
      final index = parent.nodes.indexOf(text);
      text.remove();
      parent.nodes.insertAll(index, [for (final p in pieces) _nodeOf(p)]);
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

Node _nodeOf(MarkedPiece piece) {
  if (piece.fill == null && piece.underline == null) return Text(piece.text);
  final mark = Element.tag('mark')
    ..attributes['style'] = markStyleOf(piece)
    ..append(Text(piece.text));
  final note = markNoteOf(piece);
  if (note != null) mark.attributes['title'] = note;
  return mark;
}
