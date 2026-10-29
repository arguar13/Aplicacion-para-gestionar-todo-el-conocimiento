import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_charts.dart';

import '../support/infographic_muestrario.dart';

/// Los gráficos dibujados por la app (F43): lo que pintan es lo que dicen
/// los números, se leen en voz alta y no desbordan en ningún tamaño.
void main() {
  setUpAll(loadInfographicFonts);

  final style = InfographicStyle(
    design: const InfographicDesign(style: InfographicStyleId.data),
    arrangement: InfographicAuto.arrange(
      const Infographic(
        title: 'T',
        blocks: [InfographicBlock.fact(title: 'x')],
      ),
      const InfographicDesign(style: InfographicStyleId.data),
    ),
  );

  Future<void> pumpChart(
    WidgetTester tester,
    ChartBlock chart, {
    Size size = const Size(600, 360),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: InfoChart(
              style: style,
              chart: chart,
              surface: style.palette.surfaceOnBackground,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  ChartBlock bars(int n) =>
      InfographicBlock.chart(
            title: 'Barras',
            chartKind: InfographicChartKind.bars,
            data: [
              for (var i = 0; i < n; i++)
                InfographicDatum(label: 'Dato $i', value: (i + 1) * 10.0),
            ],
          )
          as ChartBlock;

  testWidgets('las barras: una por dato, del largo de su número', (
    tester,
  ) async {
    await pumpChart(tester, bars(3));
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<InfoBarPainter>()
        .toList();
    expect(painters.map((p) => p.fraction), [
      closeTo(1 / 3, 1e-9),
      closeTo(2 / 3, 1e-9),
      1,
    ]);
    // La mayor, del color principal; las demás, del segundo.
    expect(painters.last.color, isNot(painters.first.color));
    expect(find.text('Dato 0'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('el anillo de un porcentaje, con la cifra en el medio', (
    tester,
  ) async {
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            data: [InfographicDatum(label: 'Hecho', value: 40)],
            unit: '%',
          )
          as ChartBlock,
    );
    final ring = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<InfoRingPainter>()
        .single;
    expect(ring.single, isTrue);
    final (start, sweep) = InfoRingPainter.sweeps(
      ring.fractions,
      single: true,
    ).single;
    expect(start, -math.pi / 2);
    expect(sweep, closeTo(math.pi * 2 * 0.4, 1e-9));
    expect(find.text('40 %'), findsOneWidget);
  });

  test('las partes de un anillo se reparten la vuelta entera', () {
    final sweeps = InfoRingPainter.sweeps([0.25, 0.75], single: false);
    expect(sweeps, hasLength(2));
    // Cada arco empieza donde terminó el anterior (más el respiro).
    expect(sweeps[1].$1 - sweeps[0].$1, closeTo(math.pi * 2 * 0.25, 1e-9));
    expect(sweeps[1].$2, lessThan(math.pi * 2 * 0.75));
    expect(sweeps[1].$2, greaterThan(math.pi * 2 * 0.7));
  });

  testWidgets('el pictograma pinta de color los que cuenta', (tester) async {
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            chartKind: InfographicChartKind.pictogram,
            data: [InfographicDatum(label: 'De cada 10', value: 7)],
            total: 10,
          )
          as ChartBlock,
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<InfoPictogramPainter>()
        .single;
    expect(painter.total, 10);
    expect(painter.filled, 7);
    expect(painter.color, isNot(painter.track));
    expect(find.text('7 / 10'), findsOneWidget);
  });

  test('la grilla del pictograma elige el lado más grande que entra', () {
    final (columns, side) = InfoPictogramPainter.grid(10, const Size(500, 100));
    expect(columns, 10);
    expect(side, 50);
    final (tall, tallSide) = InfoPictogramPainter.grid(
      10,
      const Size(100, 500),
    );
    expect(tall, 2);
    expect(tallSide, 50);
  });

  testWidgets('el avance mide contra su total', (tester) async {
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            chartKind: InfographicChartKind.progress,
            data: [InfographicDatum(label: 'Recorrido', value: 3)],
            total: 40,
            unit: 'años',
          )
          as ChartBlock,
    );
    final bar = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<InfoBarPainter>()
        .single;
    expect(bar.fraction, closeTo(3 / 40, 1e-9));
    expect(find.text('3 años'), findsOneWidget);
  });

  testWidgets('se leen en voz alta, con sus números', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChart(tester, bars(2));
    expect(
      find.bySemanticsLabel('Barras. Dato 0: 10; Dato 1: 20'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('ocho datos en un lugar chico no desbordan', (tester) async {
    for (final size in const [Size(160, 60), Size(90, 300), Size(400, 24)]) {
      for (final kind in InfographicChartKind.values) {
        final chart = bars(
          kind == InfographicChartKind.pictogram ? 3 : 8,
        ).copyWith(chartKind: kind, total: 20);
        await pumpChart(tester, chart, size: size);
      }
    }
  });
}
