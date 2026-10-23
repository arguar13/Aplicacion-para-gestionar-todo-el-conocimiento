import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_semantic_colors.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/app_theme_palette.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

/// El contraste de WCAG 2.1 entre [a] y [b]: de 1 (iguales) a 21. Lo que tiene
/// transparencia (`Colors.black87`) se mezcla antes con [b], que es lo que se
/// ve en pantalla.
double contrast(Color a, Color b) {
  final top = Color.alphaBlend(a, b);
  final x = top.computeLuminance();
  final y = b.computeLuminance();
  final lighter = x > y ? x : y;
  final darker = x > y ? y : x;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  /// Los seis con nombre y el brillo que tiene que dar cada uno: es de lo que
  /// depende todo lo que elige color por `Theme.brightness`.
  const named = <AppThemeChoice, Brightness>{
    AppThemeChoice.sepia: Brightness.light,
    AppThemeChoice.night: Brightness.dark,
    AppThemeChoice.forest: Brightness.dark,
    AppThemeChoice.ocean: Brightness.dark,
    AppThemeChoice.lavender: Brightness.light,
    AppThemeChoice.graphite: Brightness.dark,
  };

  group('el brillo y el modo de cada tema', () {
    test('cada tema con nombre da su brillo, en el tema y en el modo', () {
      for (final MapEntry(key: choice, value: brightness) in named.entries) {
        expect(choice.brightness, brightness, reason: choice.name);
        expect(choice.theme.brightness, brightness, reason: choice.name);
        expect(choice.darkTheme.brightness, brightness, reason: choice.name);
        expect(choice.theme.colorScheme.brightness, brightness);
        expect(
          choice.mode,
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          reason: choice.name,
        );
      }
    });

    test('Sepia y Lavanda son claros; Noche, Bosque, Océano y Grafito, '
        'oscuros', () {
      expect(AppThemeChoice.sepia.brightness, Brightness.light);
      expect(AppThemeChoice.lavender.brightness, Brightness.light);
      expect(AppThemeChoice.night.brightness, Brightness.dark);
      expect(AppThemeChoice.forest.brightness, Brightness.dark);
      expect(AppThemeChoice.ocean.brightness, Brightness.dark);
      expect(AppThemeChoice.graphite.brightness, Brightness.dark);
    });

    test(
      'el del sistema, el claro y el oscuro siguen siendo los de siempre',
      () {
        expect(AppThemeChoice.system.mode, ThemeMode.system);
        expect(AppThemeChoice.system.brightness, isNull);
        expect(AppThemeChoice.light.mode, ThemeMode.light);
        expect(AppThemeChoice.dark.mode, ThemeMode.dark);
        for (final choice in [
          AppThemeChoice.system,
          AppThemeChoice.light,
          AppThemeChoice.dark,
        ]) {
          expect(choice.palette, isNull, reason: choice.name);
          expect(choice.theme.brightness, Brightness.light);
          expect(choice.darkTheme.brightness, Brightness.dark);
          expect(
            choice.theme.colorScheme.primary,
            AppTheme.lightTheme.colorScheme.primary,
          );
          expect(
            choice.darkTheme.colorScheme.primary,
            AppTheme.darkTheme.colorScheme.primary,
          );
        }
      },
    );

    test('hay un tema con nombre por cada paleta, y cada uno con la suya', () {
      expect(
        AppThemeChoice.values.where((c) => c.palette != null),
        hasLength(AppThemePalette.values.length),
      );
      expect(
        {for (final c in AppThemeChoice.values) c.palette}..remove(null),
        AppThemePalette.values.toSet(),
      );
      expect(AppThemeChoice.sepia.palette, AppThemePalette.sepia);
      expect(AppThemeChoice.night.palette, AppThemePalette.night);
      expect(AppThemeChoice.forest.palette, AppThemePalette.forest);
      expect(AppThemeChoice.ocean.palette, AppThemePalette.ocean);
      expect(AppThemeChoice.lavender.palette, AppThemePalette.lavender);
      expect(AppThemeChoice.graphite.palette, AppThemePalette.graphite);
    });

    test('cada tema con nombre se ve con sus colores', () {
      for (final choice in named.keys) {
        final palette = choice.palette!;
        final theme = choice.theme;
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(theme.colorScheme.surface, palette.surface);
        expect(theme.colorScheme.onSurface, palette.onSurface);
        expect(theme.colorScheme.onSurfaceVariant, palette.onSurfaceVariant);
        expect(theme.colorScheme.onPrimary, palette.onPrimary);
        expect(theme.colorScheme.onSecondary, palette.onSecondary);
        expect(theme.colorScheme.outline, palette.outline);
        expect(theme.colorScheme.primary, palette.primary);
        expect(theme.colorScheme.secondary, palette.secondary);
        expect(theme.colorScheme.tertiaryContainer, palette.highlight);
        expect(theme.appBarTheme.backgroundColor, palette.surface);
        // Los dos lugares de `MaterialApp` dan el mismo tema: el modo ya
        // dice cuál se usa.
        expect(identical(choice.theme, choice.darkTheme), isTrue);
      }
    });

    test('los temas con nombre son todos distintos entre sí y de los de '
        'siempre', () {
      final looks = {
        for (final choice in AppThemeChoice.values)
          (
            choice.theme.scaffoldBackgroundColor,
            choice.theme.colorScheme.primary,
          ),
      };
      // system, light y dark comparten el claro como `theme`.
      expect(looks, hasLength(named.length + 1));
    });

    test('Noche tiene el fondo en negro puro', () {
      expect(AppThemeChoice.night.theme.scaffoldBackgroundColor, Colors.black);
    });

    test('un tema armado se reusa: no se rehace en cada reconstrucción', () {
      expect(
        identical(AppThemeChoice.sepia.theme, AppThemeChoice.sepia.theme),
        isTrue,
      );
      expect(
        identical(AppThemeChoice.light.theme, AppThemeChoice.system.theme),
        isTrue,
      );
    });
  });

  group('lo guardado', () {
    test('lo que se guardaba antes (system, light, dark) se lee igual', () {
      expect(AppThemeChoice.fromStorage('system'), AppThemeChoice.system);
      expect(AppThemeChoice.fromStorage('light'), AppThemeChoice.light);
      expect(AppThemeChoice.fromStorage('dark'), AppThemeChoice.dark);
    });

    test('cada tema se lee por su nombre', () {
      for (final choice in AppThemeChoice.values) {
        expect(AppThemeChoice.fromStorage(choice.name), choice);
      }
    });

    test('sin nada o con un valor que no se conoce, el del sistema', () {
      expect(AppThemeChoice.fromStorage(null), AppThemeChoice.system);
      expect(AppThemeChoice.fromStorage(''), AppThemeChoice.system);
      expect(AppThemeChoice.fromStorage('rosa'), AppThemeChoice.system);
    });
  });

  group('las muestras', () {
    test('el del sistema muestra el claro y el oscuro; el resto, uno', () {
      expect(AppThemeChoice.system.previews.map((t) => t.brightness), [
        Brightness.light,
        Brightness.dark,
      ]);
      expect(AppThemeChoice.light.previews.single.brightness, Brightness.light);
      expect(AppThemeChoice.dark.previews.single.brightness, Brightness.dark);
      for (final choice in named.keys) {
        expect(choice.previews, [choice.theme], reason: choice.name);
      }
    });
  });

  group('se lee bien en cada tema', () {
    /// Todos los temas, también los de siempre.
    final all = [
      for (final choice in AppThemeChoice.values)
        if (choice != AppThemeChoice.system) choice,
    ];

    test(
      'el texto sobre la superficie y el fondo, y el secundario, pasan AA',
      () {
        for (final choice in all) {
          // El claro/oscuro: el tema que se ve es `theme` o `darkTheme` según el
          // modo.
          final theme = choice.mode == ThemeMode.dark
              ? choice.darkTheme
              : choice.theme;
          final scheme = theme.colorScheme;
          final why = choice.name;
          expect(
            contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(7),
            reason: why,
          );
          expect(
            contrast(scheme.onSurface, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(7),
            reason: why,
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: why,
          );
          expect(
            contrast(scheme.onSurfaceVariant, theme.scaffoldBackgroundColor),
            greaterThanOrEqualTo(4.5),
            reason: why,
          );
        }
      },
    );

    test('los botones, los acentos y los contenedores de cada tema con nombre '
        'pasan AA', () {
      for (final choice in named.keys) {
        final theme = choice.mode == ThemeMode.dark
            ? choice.darkTheme
            : choice.theme;
        final s = theme.colorScheme;
        final why = choice.name;
        expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onSecondary, s.secondary), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onError, s.error), greaterThanOrEqualTo(4.5));
        // Un enlace o un ícono con el acento, sobre la tarjeta.
        expect(contrast(s.primary, s.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(s.secondary, s.surface), greaterThanOrEqualTo(4.5));
        for (final (fore, back) in [
          (s.onPrimaryContainer, s.primaryContainer),
          (s.onSecondaryContainer, s.secondaryContainer),
          (s.onSurface, s.surfaceContainerLow),
          (s.onSurface, s.surfaceContainer),
          (s.onSurface, s.surfaceContainerHigh),
          (s.onSurface, s.surfaceContainerHighest),
          (s.onSurfaceVariant, s.surfaceContainerHighest),
          (s.onSurface, s.tertiaryContainer),
          (s.onTertiaryContainer, s.tertiaryContainer),
          (s.onInverseSurface, s.inverseSurface),
        ]) {
          expect(
            contrast(fore, back),
            greaterThanOrEqualTo(4.5),
            reason: '$why: $fore sobre $back',
          );
        }
      }
    });

    test('las tarjetas se separan de la superficie: hay un escalón', () {
      for (final palette in AppThemePalette.values) {
        final s = palette.colorScheme;
        expect(s.surfaceContainerLow, isNot(s.surface), reason: palette.name);
        expect(
          s.surfaceContainerHighest,
          isNot(s.surfaceContainerLow),
          reason: palette.name,
        );
        expect(s.outlineVariant, isNot(s.surface), reason: palette.name);
      }
    });

    test('lo semántico (éxito y advertencia) sigue el brillo del tema', () {
      for (final MapEntry(key: choice, value: brightness) in named.entries) {
        expect(
          choice.theme.extension<AppSemanticColors>(),
          brightness == Brightness.dark
              ? AppSemanticColors.dark
              : AppSemanticColors.light,
          reason: choice.name,
        );
      }
    });

    test('los resaltadores de estudiar se leen con la letra oscura en cada '
        'tema', () {
      for (final choice in all) {
        final brightness = choice.mode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light;
        final palette = StudyPalette.of(brightness);
        for (final color in [
          palette.summary,
          palette.synthesis,
          palette.keyword,
        ]) {
          expect(
            contrast(StudyPalette.ink, color),
            greaterThanOrEqualTo(7),
            reason: '${choice.name}: $color',
          );
        }
      }
    });

    test('los subrayados a mano y el amarillo de lo que se lee tienen letra '
        'oscura legible', () {
      for (final palette in [HighlightPalette.light, HighlightPalette.dark]) {
        for (final color in HighlightColor.values) {
          expect(
            contrast(Colors.black87, palette[color]),
            greaterThanOrEqualTo(7),
            reason: '$color',
          );
        }
      }
      expect(
        contrast(Colors.black87, RenderedMarkdown.playingColor),
        greaterThanOrEqualTo(7),
      );
    });

    test('un subrayado se distingue del papel de cada tema', () {
      for (final choice in all) {
        final theme = choice.mode == ThemeMode.dark
            ? choice.darkTheme
            : choice.theme;
        final palette = HighlightPalette.forTheme(theme);
        for (final color in HighlightColor.values) {
          for (final ground in [
            theme.scaffoldBackgroundColor,
            theme.colorScheme.surface,
          ]) {
            expect(
              contrast(palette[color], ground),
              greaterThanOrEqualTo(1.06),
              reason: '${choice.name}: $color',
            );
          }
          // Y la letra oscura se sigue leyendo encima.
          expect(
            contrast(Colors.black87, palette[color]),
            greaterThanOrEqualTo(7),
            reason: '${choice.name}: $color',
          );
        }
      }
    });

    test('con el claro y el oscuro de siempre los tonos no cambian', () {
      for (final (theme, brightness) in [
        (AppTheme.lightTheme, Brightness.light),
        (AppTheme.darkTheme, Brightness.dark),
      ]) {
        for (final color in HighlightColor.values) {
          expect(
            HighlightPalette.forTheme(theme)[color],
            HighlightPalette.of(brightness)[color],
            reason: '$brightness $color',
          );
        }
      }
    });

    test('en Sepia el amarillo claro se carga para verse sobre el papel', () {
      final base = HighlightPalette.of(Brightness.light);
      final sepia = HighlightPalette.forTheme(AppThemeChoice.sepia.theme);

      expect(
        sepia[HighlightColor.lightYellow],
        isNot(base[HighlightColor.lightYellow]),
      );
    });
  });
}
