import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
