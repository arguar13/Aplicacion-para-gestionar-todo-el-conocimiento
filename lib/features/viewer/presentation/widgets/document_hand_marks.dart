import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

/// Los resaltados a mano de la persona (F38) sobre un documento real —el
/// PDF, la página web archivada—: el color con que se pintan y en qué orden.
///
/// El papel de un documento real es blanco también en modo oscuro: los
/// colores son los del tema claro, como los de lo estudiado (F36). Sin color
/// elegido —los subrayados de antes— se ve el de siempre, que es el
/// `tertiaryContainer` del tema claro.
Color handMarkColor(HighlightColor? color) => switch (color) {
  final color? => HighlightPalette.light[color],
  null => _plainTone,
};

final Color _plainTone = AppTheme.lightTheme.colorScheme.tertiaryContainer;

/// El color de la línea de un subrayado de [color]: el mismo tono, más
/// firme. Los colores del resaltador son pasteles hechos para el fondo de
/// las letras, y una línea de uno de ellos sobre el papel blanco casi no se
/// ve.
Color handMarkLine(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + 0.2).clamp(0.0, 1.0))
      .toColor();
}

/// Los resaltados de la persona de abajo hacia arriba: el más nuevo, encima,
/// donde dos se pisan. A igual fecha, por id, para que el orden no cambie
/// entre pantallas.
List<Highlight> stackedHighlights(Iterable<Highlight> highlights) {
  final stacked = highlights.toList()
    ..sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  return stacked;
}

/// El color como `#rrggbb`, para el CSS de una página web.
String cssHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
