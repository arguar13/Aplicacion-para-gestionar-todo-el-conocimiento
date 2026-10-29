import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/features/creations/design/creation_fonts.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/deck_design.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_template.dart';
import 'package:sinapsis/features/creations/presentation_deck/presentation/templates/deck_templates.dart';

/// Lo que hace falta para dibujar una diapositiva, ya resuelto: la
/// plantilla, la paleta elegida (con el color propio), la letra, la densidad
/// y las medidas del lienzo.
///
/// Las medidas están en puntos del lienzo lógico (1920×1080 o 1440×1080):
/// como el lienzo tiene siempre el mismo alto, la letra mide lo mismo en
/// 16:9 y en 4:3, y solo cambia cuánto entra a lo ancho.
@immutable
class DeckStyle {
  DeckStyle({required this.design, this.deckTitle = ''})
    : template = DeckTemplates.of(design.template),
      palette = DeckTemplates.of(
        design.template,
      ).palette(design.paletteIndex, customColor: design.customColor),
      fonts =
          CreationFontPair.fromName(design.fontPair) ??
          DeckTemplates.of(design.template).fonts;

  final DeckDesign design;
  final DeckTemplate template;
  final CreationPalette palette;
  final CreationFontPair fonts;

  /// El título del mazo, para el pie.
  final String deckTitle;

  Size get canvas =>
      Size(design.aspect.logicalWidth, design.aspect.logicalHeight);

  bool get isNarrow => design.aspect == DeckAspect.standard;

  /// Cuánto aire: multiplica los márgenes y las separaciones.
  double get spacing => switch (design.density) {
    DeckDensity.airy => 1.3,
    DeckDensity.standard => 1,
    DeckDensity.compact => 0.72,
  };

  /// Cuánto más grande o chica va la letra.
  double get typeScale => switch (design.density) {
    DeckDensity.airy => 1.06,
    DeckDensity.standard => 1,
    DeckDensity.compact => 0.88,
  };

  double get marginX => (isNarrow ? 104 : 136) * spacing;

  double get marginY => 92 * spacing;

  /// La separación común entre bloques.
  double get gap => 36 * spacing;

  /// El alto que se reserva abajo para el número y el pie.
  double get footerHeight => design.numbering || design.footer ? 56 : 0;

  double get coverTitleSize => 132 * typeScale * template.titleScale;

  double get titleSize => 80 * typeScale * template.titleScale;

  double get headingSize => 52 * typeScale;

  double get bodySize => 44 * typeScale;

  double get smallSize => 33 * typeScale;

  double get kickerSize => 25 * typeScale;

  Color get ink => palette.text;

  Color get muted => palette.muted;

  /// Un título de diapositiva de contenido.
  TextStyle title({double? size, Color? color}) =>
      fonts.displayStyle(size: size ?? titleSize, color: color ?? ink);

  /// El título de la portada, la sección y el cierre.
  TextStyle displayTitle({double? size, Color? color, bool italic = false}) =>
      fonts.displayStyle(
        size: size ?? coverTitleSize,
        color: color ?? ink,
        italic: italic,
      );

  /// El encabezado de una columna o de una tarjeta.
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

  /// El rótulo chico en mayúsculas espaciadas de arriba de un título.
  TextStyle kicker({Color? color}) => fonts.bodyStyle(
    size: kickerSize,
    color: color ?? palette.accentText,
    weight: 700,
    height: 1.2,
    tracking: 0.16,
  );

  /// Una cifra o una fecha.
  TextStyle figure({required double size, Color? color, int weight = 700}) =>
      fonts.figuresStyle(
        size: size,
        color: color ?? palette.accentText,
        weight: weight,
      );

  /// [text] en mayúsculas si la plantilla las usa en los títulos.
  String titleCase(String text) =>
      template.uppercaseTitles ? text.toUpperCase() : text;
}
