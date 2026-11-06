import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/adaptive_button_bar.dart';

/// Los botones de un aviso (F46, paso 5c): en un renglón si entran y, si no,
/// apilados, alineados y del mismo ancho, sin el hueco que dejaba un `Wrap`.
void main() {
  const first = Key('primero');
  const second = Key('segundo');

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Padding(
                // El margen de la tarjeta del lector y su relleno.
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdaptiveButtonBar(
                      children: [
                        FilledButton.icon(
                          key: first,
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Marcar con IA'),
                          onPressed: () {},
                        ),
                        OutlinedButton.icon(
                          key: second,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Abrir el documento'),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const Text('después', key: Key('despues')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

  bool stacked(WidgetTester tester) => tester
      .renderObject<RenderAdaptiveButtonBar>(find.byType(AdaptiveButtonBar))
      .stacked;

  /// Lo que se espera siempre: o juntos en un renglón, con 8 entre los dos y
  /// centrados en alto, o apilados, con 8 entre los dos, la misma izquierda y
  /// el mismo ancho —el entero—; y lo que sigue, justo debajo.
  void expectTidy(WidgetTester tester, {required double width}) {
    final a = rectOf(tester, first);
    final b = rectOf(tester, second);
    final bar = tester.getRect(find.byType(AdaptiveButtonBar));
    expect(tester.takeException(), isNull);
    if (stacked(tester)) {
      expect(a.left, 32);
      expect(b.left, 32);
      expect(a.width, width - 64);
      expect(b.width, width - 64);
      expect(b.top - a.bottom, 8);
    } else {
      expect(a.left, 32);
      expect(b.left - a.right, 8);
      expect(a.center.dy, closeTo(b.center.dy, 0.01));
    }
    expect(tester.getTopLeft(find.byKey(const Key('despues'))).dy, bar.bottom);
  }

  for (final width in [360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('a $width dp con la letra a $scale: prolijos', (
        tester,
      ) async {
        await pump(tester, width: width, textScale: scale);
        expectTidy(tester, width: width);
      });
    }
  }

  testWidgets('en un teléfono, con la letra al doble, se apilan; en una '
      'pantalla ancha van juntos', (tester) async {
    await pump(tester, width: 360, textScale: 2);
    expect(stacked(tester), isTrue);

    await pump(tester, width: 900);
    expect(stacked(tester), isFalse);
    expectTidy(tester, width: 900);
  });

  testWidgets('justo al límite: si la suma entra, juntos; un punto menos, '
      'apilados', (tester) async {
    await pump(tester, width: 900);
    final together =
        rectOf(tester, first).width + 8 + rectOf(tester, second).width;

    await pump(tester, width: together + 64);
    expect(stacked(tester), isFalse);
    await pump(tester, width: together + 63);
    expect(stacked(tester), isTrue);
  });

  testWidgets('de derecha a izquierda, el primero queda a la derecha', (
    tester,
  ) async {
    await pump(tester, width: 900, direction: TextDirection.rtl);
    final a = rectOf(tester, first);
    final b = rectOf(tester, second);
    expect(a.right, 900 - 32);
    expect(a.left - b.right, 8);
  });

  testWidgets('en un renglón, uno más bajo queda centrado en alto; '
      'apilados, uno debajo del otro', (tester) async {
    Future<void> bar(double width) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const AdaptiveButtonBar(
              children: [
                SizedBox(key: first, width: 100, height: 20),
                SizedBox(key: second, width: 100, height: 40),
              ],
            ),
          ),
        ),
      ),
    );

    await bar(300);
    expect(rectOf(tester, first), const Rect.fromLTWH(0, 10, 100, 20));
    expect(rectOf(tester, second), const Rect.fromLTWH(108, 0, 100, 40));
    expect(tester.getSize(find.byType(AdaptiveButtonBar)), const Size(300, 40));

    await bar(150);
    expect(rectOf(tester, first), const Rect.fromLTWH(0, 0, 150, 20));
    expect(rectOf(tester, second), const Rect.fromLTWH(0, 28, 150, 40));
    expect(tester.getSize(find.byType(AdaptiveButtonBar)), const Size(150, 68));
  });

  testWidgets('tocar cada uno toca ese', (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveButtonBar(
            children: [
              TextButton(
                onPressed: () => tapped += 'a',
                child: const Text('Uno'),
              ),
              TextButton(
                onPressed: () => tapped += 'b',
                child: const Text('Dos'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Dos'));
    await tester.tap(find.text('Uno'));
    expect(tapped, 'ba');
  });
}
