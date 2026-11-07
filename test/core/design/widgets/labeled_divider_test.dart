import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/labeled_divider.dart';

/// El separador con su nombre en el medio (F46, paso 5h): visto en el
/// emulador, la línea de la izquierda de «Lo creado» iba de x=34 a x=200 y la
/// de la derecha de 393 a 558, cuando tenía que llegar al borde. Las dos
/// líneas miden lo mismo, con el nombre corto, largo o con la letra al doble.
void main() {
  const width = 400.0;
  const short = 'Lo creado';
  const long =
      'Lo creado sobre este recorte, con todo lo que ya tenía y lo nuevo';

  Future<void> pump(
    WidgetTester tester,
    String label, {
    double textScale = 1,
    TextStyle? style,
  }) async {
    tester.view
      ..physicalSize = const Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LabeledDivider(label: label, style: style),
            ),
          ),
        ),
      ),
    );
  }

  List<Rect> lines(WidgetTester tester) => [
    tester.getRect(find.byType(Divider).at(0)),
    tester.getRect(find.byType(Divider).at(1)),
  ];

  for (final (name, label, scale) in [
    ('un nombre corto', short, 1.0),
    ('un nombre largo', long, 1.0),
    ('la letra al doble', short, 2.0),
    ('un nombre largo con la letra al doble', long, 2.0),
  ]) {
    testWidgets('con $name, las dos líneas miden lo mismo y llegan a los '
        'bordes', (tester) async {
      await pump(tester, label, textScale: scale);

      final [left, right] = lines(tester);
      expect(left.width, moreOrLessEquals(right.width));
      expect(left.width, greaterThan(0));
      expect(left.left, 16);
      expect(right.right, width - 16);
      // El nombre queda en el medio de la fila.
      final text = tester.getRect(find.text(label));
      expect(text.center.dx, moreOrLessEquals(width / 2));
    });
  }

  testWidgets('un nombre largo ocupa como mucho el 60 % del ancho y sigue en '
      'renglones centrados', (tester) async {
    await pump(tester, long);

    const row = width - 2 * 16;
    final text = tester.getRect(find.text(long));
    expect(
      text.width,
      lessThanOrEqualTo(row * 0.6 - 2 * LabeledDivider.gap + 0.01),
    );
    expect(tester.widget<Text>(find.text(long)).textAlign, TextAlign.center);

    // En varios renglones: más alto que un nombre de un renglón.
    await pump(tester, short);
    expect(
      text.height,
      greaterThan(tester.getRect(find.text(short)).height * 2),
    );
  });

  testWidgets('un nombre corto lleva lo que mide, sin achicar las líneas de '
      'más', (tester) async {
    await pump(tester, short);

    final [left, right] = lines(tester);
    final text = tester.getRect(find.text(short));
    expect(
      left.width + right.width + text.width + 2 * LabeledDivider.gap,
      moreOrLessEquals(width - 2 * 16),
    );
    // A 12 de cada línea, como el «o» de Capturar y «Lo creado» de antes.
    expect(text.left - left.right, moreOrLessEquals(12));
    expect(right.left - text.right, moreOrLessEquals(12));
  });

  testWidgets('sin letra elegida, la chica de la pantalla en el color de lo '
      'secundario; con una, esa', (tester) async {
    await pump(tester, short);
    final context = tester.element(find.byType(LabeledDivider));
    final theme = Theme.of(context);
    var style = tester.widget<Text>(find.text(short)).style!;
    expect(style.fontSize, theme.textTheme.bodySmall!.fontSize);
    expect(style.color, theme.colorScheme.onSurfaceVariant);

    await pump(tester, short, style: const TextStyle(fontSize: 21));
    style = tester.widget<Text>(find.text(short)).style!;
    expect(style.fontSize, 21);
  });

  testWidgets('las líneas, del color de los bordes suaves', (tester) async {
    await pump(tester, short);
    final context = tester.element(find.byType(LabeledDivider));

    for (final divider in tester.widgetList<Divider>(find.byType(Divider))) {
      expect(divider.color, Theme.of(context).colorScheme.outlineVariant);
    }
  });
}
