import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Cómo queda marcado un tramo en el documento que se descarga (F38).
enum MarkStyle {
  /// El fondo del tramo, pintado del color.
  highlight,

  /// Una línea del color debajo del tramo.
  underline,
}

/// Un resaltado para escribir en un PDF (F38): los renglones que cubre en
/// una página, con su color y su estilo.
///
/// Cada renglón es un rectángulo aparte, en coordenadas del PDF —como los de
/// las letras que da `pdfrx`—, porque un tramo que sigue en el renglón de
/// abajo no es un rectángulo: es uno por renglón.
class PdfMark {
  const PdfMark({
    required this.pageNumber,
    required this.lines,
    required this.color,
    this.style = MarkStyle.highlight,
    this.note,
  });

  /// La página, desde 1, como `PdfPage.pageNumber`.
  final int pageNumber;

  /// Un rectángulo por renglón.
  final List<PdfRect> lines;

  /// El color, en ARGB (`0xAARRGGBB`).
  final int color;

  final MarkStyle style;

  /// Lo que la persona le escribió al resaltado, si algo.
  final String? note;
}
