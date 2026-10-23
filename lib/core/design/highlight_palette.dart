import 'dart:math' as math;

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

  /// Los tonos para pintar sobre [theme] (F39): los de su brillo y, si alguno
  /// casi no se distingue del fondo de ese tema —el amarillo claro sobre el
  /// papel crema de Sepia—, el mismo tono más cargado, hasta que se vea. Con
  /// el claro y el oscuro de siempre no cambia ninguno.
  factory HighlightPalette.forTheme(ThemeData theme) {
    final base = HighlightPalette.of(theme.brightness);
    final grounds = [theme.scaffoldBackgroundColor, theme.colorScheme.surface];
    return HighlightPalette._({
      for (final entry in base._colors.entries)
        entry.key: _visibleOn(entry.value, grounds),
    });
  }

  /// El del tema claro. Es también el del documento que se descarga: el
  /// papel es blanco.
  static const light = HighlightPalette._({
    HighlightColor.lightYellow: Color(0xFFFFF3A6),
    HighlightColor.orange: Color(0xFFFFCC8A),
    HighlightColor.coral: Color(0xFFFFB0A3),
    HighlightColor.sand: Color(0xFFE3CBA3),
    HighlightColor.lime: Color(0xFFD3EC7E),
    HighlightColor.turquoise: Color(0xFF9EEDE6),
    HighlightColor.blue: Color(0xFF9DB2FF),
    HighlightColor.violet: Color(0xFFDCC8FF),
    HighlightColor.gray: Color(0xFFD0D0D6),
  });

  /// En oscuro el amarillo claro se aclara un poco más que los otros: el
  /// amarillo fuerte de lo que se lee en voz alta (`0xFFFFE066`) es muy
  /// parecido al que había y se confundían.
  static const dark = HighlightPalette._({
    HighlightColor.lightYellow: Color(0xFFFFF2A0),
    HighlightColor.orange: Color(0xFFFFB766),
    HighlightColor.coral: Color(0xFFFF9A8A),
    HighlightColor.sand: Color(0xFFD4B484),
    HighlightColor.lime: Color(0xFFBEDB5E),
    HighlightColor.turquoise: Color(0xFF7FE3DA),
    HighlightColor.blue: Color(0xFF879EFF),
    HighlightColor.violet: Color(0xFFC9AEFF),
    HighlightColor.gray: Color(0xFFB8B8C0),
  });

  final Map<HighlightColor, Color> _colors;

  Color operator [](HighlightColor color) => _colors[color]!;

  /// [tone] más cargado, sin cambiarle el matiz, hasta que se distinga de
  /// cada uno de [grounds] (la razón de contraste mínima es [_minContrast]).
  static Color _visibleOn(Color tone, List<Color> grounds) {
    bool seen(Color c) =>
        grounds.every((ground) => _contrast(c, ground) >= _minContrast);
    var hsl = HSLColor.fromColor(tone);
    for (var step = 0; step < _maxDeepening && !seen(hsl.toColor()); step++) {
      hsl = hsl
          .withLightness((hsl.lightness - 0.03).clamp(0, 1))
          .withSaturation((hsl.saturation + 0.04).clamp(0, 1));
    }
    return hsl.toColor();
  }

  /// La razón de contraste de WCAG entre [a] y [b], de 1 a 21.
  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// Un resaltador tiene que distinguirse de la hoja: el amarillo claro sobre
  /// el blanco del tema claro (~1.1) pasa; sobre el crema de Sepia (~1.04), no.
  static const _minContrast = 1.06;
  static const _maxDeepening = 12;

  /// El color de [color] o, sin ninguno, el de siempre: el
  /// `tertiaryContainer` del tema, con el que se pintaron siempre.
  static Color resolve(BuildContext context, HighlightColor? color) {
    final theme = Theme.of(context);
    return switch (color) {
      final color? => HighlightPalette.forTheme(theme)[color],
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
