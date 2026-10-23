import 'package:sinapsis/core/domain/entities/highlight_style.dart';

/// Un tramo para marcar en el documento que se descarga (F38): lo que el
/// resumen, la síntesis o las palabras clave marcaron (F36), o un subrayado
/// de la persona.
///
/// Las posiciones son del texto extraído —el `content` de la forma de texto—,
/// no del archivo original: cada formato ubica el tramo en su archivo con
/// esas posiciones y con [excerpt], el texto marcado copiado.
class DocumentMark {
  const DocumentMark({
    required this.start,
    required this.end,
    required this.excerpt,
    required this.color,
    this.style = HighlightStyle.fill,
    this.note,
  });

  /// Dónde empieza en el texto extraído.
  final int start;

  /// Dónde termina en el texto extraído (sin incluir).
  final int end;

  /// El texto marcado.
  final String excerpt;

  /// El color, en ARGB (`0xAARRGGBB`).
  final int color;

  final HighlightStyle style;

  /// Lo que la persona le escribió, si algo.
  final String? note;
}
