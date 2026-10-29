import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/design/creation_canvas.dart';

/// El lienzo lógico de lo creado (F43): se compone siempre al mismo tamaño
/// y se escala entero para caber.
void main() {
  const logical = Size(1920, 1080);

  test('la escala que cabe sin deformar', () {
    expect(CreationCanvasMath.fitScale(logical, const Size(960, 1000)), 0.5);
    expect(CreationCanvasMath.fitScale(logical, const Size(4000, 540)), 0.5);
    expect(
      CreationCanvasMath.fitScale(logical, const Size(360, double.infinity)),
      360 / 1920,
    );
    expect(CreationCanvasMath.fitScale(logical, Size.infinite), 1);
    expect(
      CreationCanvasMath.fittedSize(logical, const Size(360, 1000)),
      const Size(360, 202.5),
    );
    expect(
      CreationCanvasMath.toLogical(
        const Offset(180, 101.25),
        logical,
        const Size(360, 1000),
      ),
      const Offset(960, 540),
    );
    expect(CreationCanvasMath.pixelRatioFor(logical, 3840), 2);
  });

  testWidgets('el contenido se compone al tamaño lógico, sin la letra '
      'grande del sistema, y se ve al tamaño que cabe', (tester) async {
    late Size seen;
    late TextScaler scaler;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 360,
              height: 600,
              child: CreationCanvas(
                logicalSize: logical,
                borderRadius: BorderRadius.circular(12),
                shadow: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    seen = constraints.biggest;
                    scaler = MediaQuery.textScalerOf(context);
                    return const ColoredBox(color: Colors.red);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(seen, logical);
    expect(scaler, TextScaler.noScaling);
    expect(
      tester.getRect(find.byType(ColoredBox)).size,
      const Size(360, 202.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que asoma del lienzo no se dibuja afuera', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: CreationCanvas(logicalSize: logical, child: SizedBox()),
      ),
    );
    expect(find.byType(ClipRect), findsOneWidget);
  });
}
