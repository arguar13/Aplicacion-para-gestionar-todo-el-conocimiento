import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';

/// Un resaltado para escribir en un PDF (F38): los renglones que cubre en
/// una página, con su color y su estilo. Una nota sobre el documento entero
/// (F45, paso 8c) es una nota del PDF sola, sin renglones: solo [noteIcon].
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
    this.noteTitle,
  });

  /// La página, desde 1, como `PdfPage.pageNumber`.
  final int pageNumber;

  /// Un rectángulo por renglón; ninguno en una nota sobre el documento
  /// entero, que no marca nada.
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

  /// El título de la nota del PDF —lo que un lector muestra arriba de ella—:
  /// «Notas del documento» en una sobre el documento entero; `null` en las
  /// demás.
  final String? noteTitle;
}
