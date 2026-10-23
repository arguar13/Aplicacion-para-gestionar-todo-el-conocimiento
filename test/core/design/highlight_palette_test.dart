import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

void main() {
  test('cada color tiene su tono, distinto de los otros, en los dos temas', () {
    for (final palette in [HighlightPalette.light, HighlightPalette.dark]) {
      final tones = {for (final color in HighlightColor.values) palette[color]};
      expect(tones, hasLength(HighlightColor.values.length));
    }
    expect(
      HighlightPalette.of(Brightness.dark)[HighlightColor.orange],
      isNot(HighlightPalette.of(Brightness.light)[HighlightColor.orange]),
    );
  });

  group('la paleta de nueve (F39)', () {
    /// Distancia entre dos colores a ojo (CIE76 en Lab): bajo 10 se confunden.
    double distance(Color a, Color b) {
      List<double> lab(Color c) {
        double lin(double v) =>
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
        final r = lin(c.r);
        final g = lin(c.g);
        final bl = lin(c.b);
        double f(double t) =>
            t > 0.008856 ? pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
        final x = f((0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047);
        final y = f(0.2126 * r + 0.7152 * g + 0.0722 * bl);
        final z = f((0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883);
        return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
      }

      final la = lab(a);
      final lb = lab(b);
      return sqrt(
        pow(la[0] - lb[0], 2) + pow(la[1] - lb[1], 2) + pow(la[2] - lb[2], 2),
      );
    }

    test('son nueve, y los cuatro de antes conservan su nombre guardado', () {
      expect(HighlightColor.values, hasLength(9));
      // Se guardan por nombre: un nombre de los de antes que cambie deja sin
      // color a todos los resaltados ya hechos.
      for (final name in ['lightYellow', 'orange', 'violet', 'turquoise']) {
        expect(HighlightColor.values.byName(name).name, name);
      }
      expect(
        HighlightColor.values.map((c) => c.name),
        containsAll(['coral', 'sand', 'lime', 'blue', 'gray']),
      );
    });

    test('la letra oscura se lee sobre cada tono, en los dos temas', () {
      for (final palette in [HighlightPalette.light, HighlightPalette.dark]) {
        for (final color in HighlightColor.values) {
          final under = Color.alphaBlend(Colors.black87, palette[color]);
          final lighter = palette[color].computeLuminance() + 0.05;
          final darker = under.computeLuminance() + 0.05;
          expect(lighter / darker, greaterThan(6), reason: color.name);
        }
      }
    });

    test('se distinguen entre sí, de lo estudiado y del amarillo de lo que '
        'suena', () {
      for (final brightness in Brightness.values) {
        final palette = HighlightPalette.of(brightness);
        final study = StudyPalette.of(brightness);
        final others = <String, Color>{
          'resumen': study.summary,
          'síntesis': study.synthesis,
          'palabras clave': study.keyword,
          'lo que suena': RenderedMarkdown.playingColor,
        };
        for (final color in HighlightColor.values) {
          for (final other in HighlightColor.values) {
            if (other.index <= color.index) continue;
            expect(
              distance(palette[color], palette[other]),
              greaterThan(14),
              reason: '${color.name} / ${other.name} en $brightness',
            );
          }
          others.forEach((name, tone) {
            expect(
              distance(palette[color], tone),
              greaterThan(14),
              reason: '${color.name} / $name en $brightness',
            );
          });
        }
      }
    });
  });

  testWidgets('sin color elegido se ve el de siempre; con color, el suyo', (
    tester,
  ) async {
    late BuildContext context;
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      HighlightPalette.resolve(context, null),
      theme.colorScheme.tertiaryContainer,
    );
    expect(
      HighlightPalette.resolve(context, HighlightColor.violet),
      HighlightPalette.light[HighlightColor.violet],
    );
  });

  testWidgets('sobre el papel crema de Sepia el amarillo claro se carga para '
      'verse, y el de siempre no cambia (F39)', (tester) async {
    late BuildContext context;
    Future<void> pumpWith(ThemeData theme) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    await pumpWith(AppTheme.lightTheme);
    expect(
      HighlightPalette.resolve(context, HighlightColor.lightYellow),
      HighlightPalette.light[HighlightColor.lightYellow],
    );

    await pumpWith(AppThemeChoice.sepia.theme);
    await tester.pumpAndSettle();
    expect(
      HighlightPalette.resolve(context, HighlightColor.lightYellow),
      HighlightPalette.forTheme(
        AppThemeChoice.sepia.theme,
      )[HighlightColor.lightYellow],
    );
    expect(
      HighlightPalette.resolve(context, HighlightColor.lightYellow),
      isNot(HighlightPalette.light[HighlightColor.lightYellow]),
    );
  });

  group('la línea de un subrayado (F38)', () {
    Future<BuildContext> pumpWith(WidgetTester tester, ThemeData theme) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return context;
    }

    testWidgets('en el tema claro es más oscura que el tono, para que se '
        'vea sobre el papel', (tester) async {
      final context = await pumpWith(tester, ThemeData.light());

      for (final color in HighlightColor.values) {
        final tone = HighlightPalette.resolve(context, color);
        final line = HighlightPalette.line(context, color);
        expect(
          HSLColor.fromColor(line).lightness,
          lessThan(HSLColor.fromColor(tone).lightness - 0.2),
        );
        expect(line, isNot(HighlightPalette.line(context, null)));
      }
    });

    testWidgets('en el tema oscuro es el tono mismo', (tester) async {
      final context = await pumpWith(tester, ThemeData.dark());

      for (final color in HighlightColor.values) {
        expect(
          HighlightPalette.line(context, color),
          HighlightPalette.resolve(context, color),
        );
      }
    });

    testWidgets('sin color elegido parte del color de siempre', (tester) async {
      final context = await pumpWith(tester, ThemeData.light());

      expect(
        HSLColor.fromColor(HighlightPalette.line(context, null)).lightness,
        lessThan(
          HSLColor.fromColor(HighlightPalette.resolve(context, null)).lightness,
        ),
      );
    });
  });

  group('sobre papel —el PDF, la página web, lo que se descarga—', () {
    testWidgets('es lo que se ve en la pantalla con el tema claro, aunque la '
        'app esté en modo oscuro', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      for (final color in [...HighlightColor.values, null]) {
        expect(
          HighlightPalette.onPaper(color),
          HighlightPalette.resolve(context, color),
        );
        expect(
          HighlightPalette.lineOnPaper(color),
          HighlightPalette.line(context, color),
        );
      }
    });

    test('la línea es más oscura que el tono y del mismo matiz', () {
      for (final color in HighlightColor.values) {
        final tone = HSLColor.fromColor(HighlightPalette.onPaper(color));
        final line = HSLColor.fromColor(HighlightPalette.lineOnPaper(color));

        expect(line.lightness, lessThan(tone.lightness - 0.2));
        expect((line.hue - tone.hue).abs(), lessThan(1));
      }
    });
  });
}
