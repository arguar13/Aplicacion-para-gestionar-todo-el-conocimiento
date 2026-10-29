import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_palette.dart';

/// Los colores de lo creado (F43): el contraste se mide como en WCAG 2, y
/// cada texto que la paleta pone sobre un color se lee (4,5:1 o más).
void main() {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);

  /// Colores de todo el círculo, en varias luces: los que podría elegir
  /// alguien como color propio.
  final sweep = [
    for (var hue = 0; hue < 360; hue += 15)
      for (final light in [0.15, 0.3, 0.45, 0.55, 0.7, 0.85])
        HSLColor.fromAHSL(1, hue.toDouble(), 0.75, light).toColor(),
    for (var gray = 0; gray <= 255; gray += 5)
      Color.fromARGB(255, gray, gray, gray),
  ];

  test('la razón de contraste es la de WCAG', () {
    expect(CreationContrast.ratio(black, white), closeTo(21, 0.01));
    expect(CreationContrast.ratio(white, white), closeTo(1, 0.001));
    expect(CreationContrast.ratio(white, black), closeTo(21, 0.01));
    // El gris #767676 es el más claro que pasa 4,5:1 sobre blanco.
    expect(
      CreationContrast.ratio(const Color(0xFF767676), white),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('el texto sobre cualquier color se lee', () {
    for (final color in sweep) {
      final on = CreationContrast.readableOn(color);
      expect(
        CreationContrast.ratio(on, color),
        greaterThanOrEqualTo(4.5),
        reason: 'sobre $color',
      );
    }
  });

  test('ensure lleva un color hasta el contraste pedido', () {
    for (final background in sweep) {
      for (final color in [
        const Color(0xFFE53935),
        const Color(0xFF808080),
        background,
      ]) {
        final fixed = CreationContrast.ensure(color, background);
        expect(
          CreationContrast.ratio(fixed, background),
          greaterThanOrEqualTo(4.5),
          reason: '$color sobre $background',
        );
      }
    }
  });

  test('un color que ya cumple no se toca', () {
    expect(CreationContrast.ensure(black, white), black);
  });

  const light = CreationPalette(
    background: Color(0xFFF7F4EE),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF1F3A5F),
    accent: Color(0xFFE9B44C),
    text: Color(0xFF1A1A1A),
    muted: Color(0xFF5E5A55),
  );
  const dark = CreationPalette(
    background: Color(0xFF0B1026),
    surface: Color(0x24FFFFFF),
    primary: Color(0xFFE8C27A),
    secondary: Color(0xFF8FA8FF),
    accent: Color(0xFFF2D9A6),
    text: Color(0xFFEEF0F8),
    muted: Color(0xFFA8AFC9),
  );

  test('la superficie translúcida se mide sobre el fondo', () {
    expect(dark.surfaceOnBackground.a, 1);
    expect(dark.surfaceOnBackground, isNot(dark.background));
    expect(light.isDark, isFalse);
    expect(dark.isDark, isTrue);
  });

  test('un color propio tiñe y deja todo legible, en claro y en oscuro', () {
    for (final palette in [light, dark]) {
      for (final seed in sweep) {
        final custom = palette.withCustomColor(seed);
        // La luz de la diapositiva no cambia.
        expect(custom.background, palette.background);
        expect(custom.surface, palette.surface);
        for (final (name, fg, minimum) in [
          ('texto', custom.text, 7.0),
          ('tenue', custom.muted, 4.5),
          ('acento', custom.accentText, 4.5),
        ]) {
          for (final bg in [custom.background, custom.surfaceOnBackground]) {
            expect(
              CreationContrast.ratio(fg, bg),
              greaterThanOrEqualTo(minimum),
              reason: '$name con $seed sobre $bg',
            );
          }
        }
        for (final fill in [custom.primary, custom.secondary, custom.accent]) {
          expect(
            CreationContrast.ratio(CreationContrast.readableOn(fill), fill),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    }
  });

  test('igualdad por valor', () {
    expect(light.copyWith(), light);
    expect(light.copyWith(primary: white), isNot(light));
    expect(light.hashCode, light.copyWith().hashCode);
  });
}
