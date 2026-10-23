import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/highlight_palette.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

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
