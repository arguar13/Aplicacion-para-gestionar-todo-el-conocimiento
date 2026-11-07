import 'package:flutter/material.dart';

/// Los colores de un control que flota encima de cualquier cosa —una página
/// blanca, una foto, un video negro—, como el botón grande del visor
/// embebido («Ver la página», «Leer como libro», «Ampliar») y el de expandir
/// de la esquina (F46, paso 5i).
///
/// Existe porque esos botones eran letra blanca sobre negro al 40 %: encima
/// de una página blanca el fondo quedaba gris claro, y el contraste, en 2,9 a
/// 1, por debajo del 4,5 a 1 que pide WCAG AA para letra de ese tamaño. El
/// fondo de un control así no lo elige quien lo pone: lo pone lo que tenga
/// debajo, y tiene que leerse sobre lo peor.
///
/// Los colores salen del tema —`inverseSurface` de fondo y `onInverseSurface`
/// de letra, el par de Material para lo que va encima del contenido, como un
/// aviso—, así que siguen al claro, al oscuro y a cada tema con nombre. El
/// fondo es lo más transparente que se pueda —para que se vea el original
/// debajo, como siempre— **sin bajar de [minContrast] sobre ningún fondo**:
/// ver [OverlayControlColors.of].
@immutable
class OverlayControlColors {
  const OverlayControlColors._({
    required this.background,
    required this.foreground,
  });

  /// Los de [scheme], calculados una vez por esquema.
  ///
  /// Un fondo con transparencia sobre lo que haya debajo se ve, canal por
  /// canal, entre como se ve sobre negro y como se ve sobre blanco; y la
  /// luminancia sube con cada canal. Así, lo que se ve de él queda siempre
  /// entre esas dos luminancias, y si la letra tiene, contra las dos puntas,
  /// al menos [minContrast] —y no cae entre ellas— lo tiene contra cualquier
  /// cosa de abajo. Se busca la menor opacidad que lo cumple, de a un 1 %.
  /// Si ni el fondo entero alcanza —un tema cuyo par no contrasta lo
  /// suficiente—, la letra pasa a blanco o negro, la que más contraste.
  factory OverlayControlColors.of(ColorScheme scheme) =>
      _cache[scheme] ??= OverlayControlColors._compute(scheme);

  /// Ver [OverlayControlColors.of].
  factory OverlayControlColors._compute(ColorScheme scheme) {
    final base = scheme.inverseSurface.withValues(alpha: 1);
    var foreground = scheme.onInverseSurface.withValues(alpha: 1);
    if (!readableOverAnything(foreground, base)) {
      foreground =
          _contrast(Colors.white, base) >= _contrast(Colors.black, base)
          ? Colors.white
          : Colors.black;
    }
    for (var step = (_minAlpha * 100).round(); step < 100; step++) {
      final background = base.withValues(alpha: step / 100);
      if (readableOverAnything(foreground, background)) {
        return OverlayControlColors._(
          background: background,
          foreground: foreground,
        );
      }
    }
    return OverlayControlColors._(background: base, foreground: foreground);
  }

  /// El fondo, con su transparencia.
  final Color background;

  /// La letra y el ícono, opacos.
  final Color foreground;

  /// El contraste mínimo de WCAG AA para letra que no es grande.
  static const minContrast = 4.5;

  /// La opacidad más baja que se prueba: menos que esto ya no se lee como un
  /// botón, aunque el contraste diera.
  static const _minAlpha = 0.5;

  static final _cache = Expando<OverlayControlColors>();

  /// Si [foreground] se lee con al menos [minContrast] sobre [background]
  /// —con su transparencia— ponga lo que se ponga debajo: ver
  /// [OverlayControlColors.of].
  ///
  /// Alcanza con las dos puntas: si la letra tiene [minContrast] contra las
  /// dos, no puede caer entre ellas —haría falta que de una punta a la otra
  /// hubiera más de 20 a 1, y con un fondo de al menos la mitad de opaco no
  /// hay ni 5 a 1—, así que contra todo lo de en medio tiene más.
  static bool readableOverAnything(Color foreground, Color background) =>
      _contrast(foreground, Color.alphaBlend(background, Colors.white)) >=
          minContrast &&
      _contrast(foreground, Color.alphaBlend(background, Colors.black)) >=
          minContrast;

  /// El contraste de WCAG 2.1 entre dos colores opacos.
  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
  }
}
