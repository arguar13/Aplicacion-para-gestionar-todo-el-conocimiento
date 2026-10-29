import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style_spec.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_styles.dart';

/// Lo que hace falta para dibujar una lámina, ya resuelto: el estilo de
/// verdad (sin «Automático»), la paleta elegida con el color propio, la
/// letra, los íconos, el fondo y las medidas del lienzo.
///
/// Las medidas están en puntos del lienzo lógico. Como las tres
/// orientaciones tienen la misma superficie, la letra mide lo mismo en las
/// tres; lo que cambia es el aire: con pocos bloques la letra crece un poco
/// para que no queden cajas grandes con texto chico, y con muchos se achica.
@immutable
class InfographicStyle {
  InfographicStyle({required this.design, required this.arrangement})
    : spec = InfographicStyles.of(arrangement.style),
      palette = InfographicStyles.of(
        arrangement.style,
      ).palette(design.paletteIndex, customColor: design.customColor),
      fonts =
          CreationFontPair.fromName(design.fontPair) ??
          InfographicStyles.of(arrangement.style).fonts;

  final InfographicDesign design;
  final InfographicArrangement arrangement;
  final InfographicStyleSpec spec;
  final CreationPalette palette;
  final CreationFontPair fonts;

  InfographicOrientation get orientation => design.orientation;

  Size get canvas => Size(orientation.logicalWidth, orientation.logicalHeight);

  bool get isPortrait => orientation == InfographicOrientation.portrait;

  bool get isLandscape => orientation == InfographicOrientation.landscape;

  InfographicIconLook get iconLook => design.iconLook ?? spec.iconLook;

  InfographicBackground get background => design.background ?? spec.background;

  bool get showDetails => arrangement.showDetails;

  /// Cuánto crece o se achica la letra de los bloques según cuántos hay.
  double get typeScale => switch (arrangement.blocks.length) {
    <= 3 => 1.22,
    4 => 1.14,
    5 => 1.07,
    6 => 1,
    <= 8 => 0.94,
    _ => 0.88,
  };

  double get marginX => isLandscape ? 88 : 68;

  double get marginY => isPortrait ? 84 : 64;

  /// La separación común entre bloques.
  double get gap => 26;

  double get titleSize =>
      (isLandscape ? 84 : 90) * spec.titleScale * (isPortrait ? 1 : 0.96);

  double get subtitleSize => 34;

  double get kickerSize => 22;

  double get headingSize => 37 * typeScale;

  double get bodySize => 27 * typeScale;

  double get smallSize => 23 * typeScale;

  /// La cifra de un bloque de cifras.
  double get figureSize => 84 * typeScale;

  /// El lado de un ícono de bloque, con su disco.
  double get iconSize => 76 * typeScale;

  Color get ink => palette.text;

  Color get muted => palette.muted;

  /// Los tres colores con que se distinguen los bloques, en orden.
  List<Color> get tints => [palette.primary, palette.secondary, palette.accent];

  Color tint(int index) => tints[index % tints.length];

  /// El título de la lámina.
  TextStyle title({double? size, Color? color}) =>
      fonts.displayStyle(size: size ?? titleSize, color: color ?? ink);

  /// La bajada de la cabecera.
  TextStyle subtitle({Color? color}) =>
      fonts.bodyStyle(size: subtitleSize, color: color ?? muted, height: 1.25);

  /// El rótulo chico en mayúsculas espaciadas de arriba del título.
  TextStyle kicker({Color? color}) => fonts.bodyStyle(
    size: kickerSize,
    color: color ?? palette.accentText,
    weight: 700,
    height: 1.2,
    tracking: 0.16,
  );

  /// El título de un bloque.
  TextStyle heading({double? size, Color? color}) => fonts.displayStyle(
    size: size ?? headingSize,
    color: color ?? ink,
    height: 1.12,
  );

  TextStyle body({double? size, Color? color, int weight = 400}) => fonts
      .bodyStyle(size: size ?? bodySize, color: color ?? ink, weight: weight);

  TextStyle small({double? size, Color? color, int weight = 400}) =>
      fonts.bodyStyle(
        size: size ?? smallSize,
        color: color ?? muted,
        weight: weight,
      );

  /// Una cifra o una fecha.
  TextStyle figure({double? size, Color? color, int weight = 800}) =>
      fonts.figuresStyle(
        size: size ?? figureSize,
        color: color ?? palette.accentText,
        weight: weight,
      );

  /// [text] en mayúsculas si el estilo las usa en los títulos.
  String titleCase(String text) =>
      spec.uppercaseTitles ? text.toUpperCase() : text;
}
