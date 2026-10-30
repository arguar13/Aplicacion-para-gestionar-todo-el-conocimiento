import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// Los colores de una creación (F43): una diapositiva, una lámina.
///
/// Siete colores que se eligen a mano en cada plantilla —el fondo, la
/// superficie de los paneles, el primario, el secundario, el acento, el
/// texto y el texto tenue— y el resto se deriva de ellos con contraste
/// comprobado: [onPrimary], [onSecondary], [onAccent] y [accentText]. Así un
/// color propio que elija la persona (ver [withCustomColor]) nunca deja un
/// texto ilegible encima.
///
/// La superficie puede ser translúcida (el vidrio): todo contraste contra ella
/// se mide sobre el fondo, con [surfaceOnBackground].
@immutable
class CreationPalette {
  const CreationPalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color text;
  final Color muted;

  /// Si el fondo es oscuro: decide hacia dónde se corrigen los colores.
  bool get isDark => background.computeLuminance() < 0.18;

  /// La superficie tal como se ve sobre el fondo.
  Color get surfaceOnBackground => Color.alphaBlend(surface, background);

  /// El texto sobre un relleno del primario.
  Color get onPrimary => CreationContrast.readableOn(primary);

  Color get onSecondary => CreationContrast.readableOn(secondary);

  Color get onAccent => CreationContrast.readableOn(accent);

  /// El primario como color de un texto chico sobre el fondo y la superficie
  /// (un rótulo, una cifra), llevado hasta 4,5:1 si hace falta.
  Color get accentText =>
      CreationContrast.ensureOnAll(primary, [background, surfaceOnBackground]);

  /// El papel de una nota adhesiva (F45): la superficie teñida del acento, lo
  /// justo para que se vea de color sin que el texto deje de leerse a 7:1 ni
  /// el tenue a 4,5:1.
  Color get noteColor {
    final base = surfaceOnBackground;
    for (var tint = 0.3; tint > 0; tint -= 0.02) {
      final paper = Color.lerp(base, accent, tint)!;
      if (CreationContrast.ratio(text, paper) >= 7 &&
          CreationContrast.ratio(muted, paper) >= 4.5) {
        return paper;
      }
    }
    return base;
  }

  /// La paleta con el texto y el texto tenue llevados hasta 4,5:1 sobre el
  /// fondo y la superficie. Las paletas escritas a mano ya cumplen —lo
  /// comprueba la prueba de las plantillas—; esto es para las que se arman
  /// con un color propio.
  CreationPalette readable() => copyWith(
    text: CreationContrast.ensureOnAll(text, [
      background,
      surfaceOnBackground,
    ], minimum: 7),
    muted: CreationContrast.ensureOnAll(muted, [
      background,
      surfaceOnBackground,
    ]),
  );

  /// La paleta con [seed] como color propio: el primario es [seed]; el acento
  /// y el secundario, variaciones del mismo tono, para que todo combine. El
  /// fondo, la superficie y el texto se quedan los de la plantilla: el color
  /// propio tiñe, no cambia la luz de la diapositiva.
  CreationPalette withCustomColor(Color seed) {
    final hsl = HSLColor.fromColor(seed.withValues(alpha: 1));
    final accent = hsl
        .withHue((hsl.hue + 28) % 360)
        .withLightness((hsl.lightness + (isDark ? 0.12 : -0.06)).clamp(0, 1));
    final secondary = hsl
        .withHue((hsl.hue + 330) % 360)
        .withSaturation((hsl.saturation * 0.7).clamp(0, 1));
    return copyWith(
      primary: hsl.toColor(),
      accent: accent.toColor(),
      secondary: secondary.toColor(),
    ).readable();
  }

  CreationPalette copyWith({
    Color? background,
    Color? surface,
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? text,
    Color? muted,
  }) => CreationPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    accent: accent ?? this.accent,
    text: text ?? this.text,
    muted: muted ?? this.muted,
  );

  /// Los colores que se muestran en la muestra de una paleta, en orden.
  List<Color> get swatch => [background, primary, secondary, accent];

  @override
  bool operator ==(Object other) =>
      other is CreationPalette &&
      other.background == background &&
      other.surface == surface &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.accent == accent &&
      other.text == text &&
      other.muted == muted;

  @override
  int get hashCode =>
      Object.hash(background, surface, primary, secondary, accent, text, muted);
}

/// El contraste entre colores, como lo define WCAG 2: la razón entre las
/// luminancias relativas, de 1:1 a 21:1. AA pide 4,5:1 para el texto común y
/// 3:1 para el grande.
abstract final class CreationContrast {
  /// El texto claro de siempre.
  static const light = Color(0xFFFFFFFF);

  /// El texto oscuro de siempre: casi negro, que cansa menos que el negro.
  static const dark = Color(0xFF14161A);

  static double ratio(Color a, Color b) {
    final la = a.withValues(alpha: 1).computeLuminance();
    final lb = b.withValues(alpha: 1).computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// El claro o el oscuro, el que más contraste tenga sobre [background].
  /// En los tonos medios, donde ninguno de los dos llega a 4,5:1, el negro
  /// puro: con él siempre se llega (el peor caso del blanco o el negro es
  /// 4,58:1).
  static Color readableOn(
    Color background, {
    Color lightColor = light,
    Color darkColor = dark,
  }) {
    final best = ratio(lightColor, background) >= ratio(darkColor, background)
        ? lightColor
        : darkColor;
    if (ratio(best, background) >= 4.5) return best;
    const black = Color(0xFF000000);
    return ratio(black, background) > ratio(best, background) ? black : best;
  }

  /// [color], o el mismo tono llevado de a poco hacia el blanco o el negro
  /// —hacia donde más contraste dé— hasta tener [minimum] sobre
  /// [background]. Si ni en el extremo llega, el extremo.
  static Color ensure(Color color, Color background, {double minimum = 4.5}) =>
      ensureOnAll(color, [background], minimum: minimum);

  /// Como [ensure], pero contra todos los [backgrounds] a la vez.
  static Color ensureOnAll(
    Color color,
    List<Color> backgrounds, {
    double minimum = 4.5,
  }) {
    double worst(Color c) =>
        backgrounds.map((b) => ratio(c, b)).reduce((a, b) => a < b ? a : b);
    if (worst(color) >= minimum) return color;
    // Hacia el extremo que más contraste dé con el fondo más exigente: el
    // blanco, el casi negro de siempre o, en los tonos medios donde ninguno
    // de los dos llega, el negro puro.
    var towards = light;
    for (final extreme in const [dark, Color(0xFF000000)]) {
      if (worst(extreme) > worst(towards)) towards = extreme;
    }
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(color, towards, step / 20)!;
      if (worst(candidate) >= minimum) return candidate;
    }
    return towards;
  }
}
