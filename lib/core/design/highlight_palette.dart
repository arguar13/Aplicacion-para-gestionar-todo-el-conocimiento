import 'package:flutter/material.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

/// Cómo se ve cada color del resaltador a mano (F38, decisión A): en la
/// pantalla y en el documento que se descarga, el mismo tono.
///
/// Como los de lo estudiado (`StudyPalette`), la letra va oscura encima
/// también en modo oscuro: un resaltador sobre papel se lee igual en los dos.
/// Sin color elegido —todos los subrayados de antes— se ve con el color de
/// siempre: ver [resolve].
@immutable
class HighlightPalette {
  const HighlightPalette._(this._colors);

  factory HighlightPalette.of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// El del tema claro. Es también el del documento que se descarga: el
  /// papel es blanco.
  static const light = HighlightPalette._({
    HighlightColor.lightYellow: Color(0xFFFFF3A6),
    HighlightColor.orange: Color(0xFFFFCC8A),
    HighlightColor.violet: Color(0xFFDCC8FF),
    HighlightColor.turquoise: Color(0xFF9EEDE6),
  });

  static const dark = HighlightPalette._({
    HighlightColor.lightYellow: Color(0xFFFFEB7A),
    HighlightColor.orange: Color(0xFFFFB766),
    HighlightColor.violet: Color(0xFFC9AEFF),
    HighlightColor.turquoise: Color(0xFF7FE3DA),
  });

  final Map<HighlightColor, Color> _colors;

  Color operator [](HighlightColor color) => _colors[color]!;

  /// El color de [color] o, sin ninguno, el de siempre: el
  /// `tertiaryContainer` del tema, con el que se pintaron siempre.
  static Color resolve(BuildContext context, HighlightColor? color) {
    final theme = Theme.of(context);
    return switch (color) {
      final color? => HighlightPalette.of(theme.brightness)[color],
      null => theme.colorScheme.tertiaryContainer,
    };
  }

  /// El color de [color] sobre papel —el PDF, la página web archivada, el
  /// archivo que se descarga—: el del tema claro, también con la app en modo
  /// oscuro, porque la hoja es blanca igual. Sin color, el de siempre del
  /// tema claro.
  static Color onPaper(HighlightColor? color) => switch (color) {
    final color? => light[color],
    null => _paperPlain,
  };

  /// Armar el tema entero es caro: se toma una vez.
  static final Color _paperPlain =
      AppTheme.lightTheme.colorScheme.tertiaryContainer;

  /// El color de la línea de un subrayado de [color] (F38). Un tono de
  /// resaltador es clarísimo y, como línea fina sobre el papel claro, casi
  /// no se ve: en el tema claro se oscurece hasta que la línea se distinga
  /// (ver [lineOf]); en el oscuro el tono ya contrasta con el fondo y se deja
  /// como está.
  static Color line(BuildContext context, HighlightColor? color) {
    final base = resolve(context, color);
    return Theme.of(context).brightness == Brightness.dark
        ? base
        : lineOf(base);
  }

  /// La línea de un subrayado de [color] sobre papel, que es claro siempre:
  /// la misma que en la pantalla con el tema claro.
  static Color lineOnPaper(HighlightColor? color) => lineOf(onPaper(color));

  /// [base] oscurecido para que una línea fina de ese tono se vea sobre un
  /// fondo claro, sin cambiarle el matiz.
  static Color lineOf(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness(hsl.lightness * _lineDarkening).toColor();
  }

  static const _lineDarkening = 0.55;
}
