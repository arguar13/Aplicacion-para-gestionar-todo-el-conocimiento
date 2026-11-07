import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/overlay_control_colors.dart';

/// El contraste de WCAG 2.1 de [foreground] sobre [background] —con su
/// transparencia— puesto encima de [under]: lo que se ve en pantalla.
double contrastOver(Color foreground, Color background, Color under) {
  final shown = Color.alphaBlend(background, under);
  final x = foreground.computeLuminance();
  final y = shown.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

/// Los colores de un control que flota encima de cualquier cosa (F46, paso
/// 5i): se leen con al menos 4,5 a 1 sobre lo peor que puede haber debajo, en
/// todos los temas.
void main() {
  final schemes = <String, ColorScheme>{
    for (final choice in AppThemeChoice.values) ...{
      '${choice.name} (claro)': choice.theme.colorScheme,
      '${choice.name} (oscuro)': choice.darkTheme.colorScheme,
    },
  };

  test('sobre blanco y sobre negro, al menos 4,5 a 1 en cada tema, y '
      'semitransparente: el original se ve debajo', () {
    for (final MapEntry(key: name, value: scheme) in schemes.entries) {
      final colors = OverlayControlColors.of(scheme);
      for (final under in [Colors.white, Colors.black]) {
        expect(
          contrastOver(colors.foreground, colors.background, under),
          greaterThanOrEqualTo(4.5),
          reason: '$name sobre $under',
        );
      }
      expect(colors.background.a, lessThan(1), reason: name);
      expect(colors.background.a, greaterThanOrEqualTo(0.5), reason: name);
      expect(colors.foreground.a, 1, reason: name);
    }
  });

  test('sobre cualquier gris de en medio también: la letra no cae entre lo '
      'que se ve sobre blanco y sobre negro', () {
    for (final MapEntry(key: name, value: scheme) in schemes.entries) {
      final colors = OverlayControlColors.of(scheme);
      for (var level = 0; level <= 255; level += 5) {
        final under = Color.fromARGB(255, level, level, level);
        expect(
          contrastOver(colors.foreground, colors.background, under),
          greaterThanOrEqualTo(4.5),
          reason: '$name sobre gris $level',
        );
      }
      // Y sobre lo más saturado: la foto amarilla de Fotosíntesis.
      for (final under in [
        const Color(0xFFFFEB3B),
        const Color(0xFF00FF00),
        const Color(0xFF0000FF),
        const Color(0xFFFF0000),
      ]) {
        expect(
          contrastOver(colors.foreground, colors.background, under),
          greaterThanOrEqualTo(4.5),
          reason: '$name sobre $under',
        );
      }
    }
  });

  test('la menor opacidad que alcanza: un punto menos ya no se lee sobre lo '
      'peor', () {
    final colors = OverlayControlColors.of(
      AppThemeChoice.light.theme.colorScheme,
    );
    final lighter = colors.background.withValues(
      alpha: colors.background.a - 0.01,
    );
    expect(
      OverlayControlColors.readableOverAnything(colors.foreground, lighter),
      isFalse,
    );
    expect(
      OverlayControlColors.readableOverAnything(
        colors.foreground,
        colors.background,
      ),
      isTrue,
    );
  });

  test('del tema: el fondo es su inverseSurface y la letra su '
      'onInverseSurface', () {
    final scheme = AppThemeChoice.dark.darkTheme.colorScheme;
    final colors = OverlayControlColors.of(scheme);
    expect(colors.background.withValues(alpha: 1), scheme.inverseSurface);
    expect(colors.foreground, scheme.onInverseSurface);
  });

  test('un tema cuyo par no contrasta lo suficiente pasa a letra blanca o '
      'negra, y sigue leyéndose', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal).copyWith(
      inverseSurface: const Color(0xFF777777),
      onInverseSurface: const Color(0xFF888888),
    );
    final colors = OverlayControlColors.of(scheme);
    expect(colors.foreground, anyOf(Colors.white, Colors.black));
    for (final under in [Colors.white, Colors.black]) {
      expect(
        contrastOver(colors.foreground, colors.background, under),
        greaterThanOrEqualTo(4.5),
        reason: '$under',
      );
    }
  });
}
