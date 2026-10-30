import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';

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
    this.style = HighlightStyle.fill,
    this.note,
    this.noteIcon,
  });

  /// La página, desde 1, como `PdfPage.pageNumber`.
  final int pageNumber;

  /// Un rectángulo por renglón.
  final List<PdfRect> lines;

  /// El color, en ARGB (`0xAARRGGBB`).
  final int color;

  final HighlightStyle style;

  /// Lo que la persona le escribió al resaltado, si algo.
  final String? note;

  /// Con una nota en el texto (F45, mejora 19): dónde va su ícono. Entonces
  /// [note] no va en el resaltado sino en una nota del PDF —la que se abre
  /// con un toque en cualquier lector— en ese lugar, del mismo color.
  final PdfRect? noteIcon;
}
