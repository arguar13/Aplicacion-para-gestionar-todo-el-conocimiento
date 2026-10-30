import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_auto.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_design.dart';
import 'package:sinapsis/features/creations/infographic/presentation/styles/infographic_style.dart';
import 'package:sinapsis/features/creations/infographic/presentation/widgets/infographic_charts.dart';

import '../support/infographic_muestrario.dart';

/// Los gráficos dibujados por la app (F43, y los cuatro de F45): lo que
/// pintan es lo que dicen los números, se leen en voz alta y no desbordan en
/// ningún tamaño.
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

  // -------------------------------------------------------------------
  // Los cuatro de F45.

  List<T> paintersOf<T>(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<T>()
      .toList();

  testWidgets('las columnas: una por dato, del alto de su número, con su '
      'cifra y su rótulo', (tester) async {
    await pumpChart(
      tester,
      bars(3).copyWith(chartKind: InfographicChartKind.columns),
    );
    final columns = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .toList();
    expect(columns, hasLength(3));
    // La más alta es la del dato mayor.
    final heights = [
      for (final c in find.byType(Container).evaluate())
        if ((c.widget as Container).decoration is BoxDecoration)
          (c.renderObject! as RenderBox).size.height,
    ];
    expect(heights[0], lessThan(heights[1]));
    expect(heights[1], lessThan(heights[2]));
    expect(heights[0] / heights[2], closeTo(1 / 3, 0.02));
    expect(find.text('Dato 2'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('los anillos concéntricos: una vuelta por dato, contra el mismo '
      'total, sin pisarse', (tester) async {
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            chartKind: InfographicChartKind.rings,
            data: [
              InfographicDatum(label: 'Uno', value: 80),
              InfographicDatum(label: 'Dos', value: 50),
              InfographicDatum(label: 'Tres', value: 20),
            ],
            unit: '%',
          )
          as ChartBlock,
    );
    final rings = paintersOf<InfoRingsPainter>(tester).single;
    expect(rings.fractions, [0.8, 0.5, 0.2]);
    for (var i = 0; i < 2; i++) {
      final outer = InfoRingsPainter.ring(i, 3, 300);
      final inner = InfoRingsPainter.ring(i + 1, 3, 300);
      expect(
        outer.radius - outer.stroke / 2,
        greaterThan(inner.radius + inner.stroke / 2),
      );
    }
    final last = InfoRingsPainter.ring(2, 3, 300);
    expect(last.radius - last.stroke / 2, greaterThan(0));
    expect(find.text('Uno · 80 %'), findsOneWidget);
  });

  test(
    'la cuadrícula de cien pinta los cien, repartidos por el mayor resto',
    () {
      int count(List<int> cells, int part) =>
          cells.where((c) => c == part).length;
      final thirds = InfoWafflePainter.cellsOf([0.33, 0.33, 0.34]);
      expect(thirds, hasLength(100));
      expect(
        [count(thirds, 0), count(thirds, 1), count(thirds, 2)],
        [33, 33, 34],
      );
      expect(count(thirds, -1), 0);
      final eighths = InfoWafflePainter.cellsOf([0.125, 0.125, 0.75]);
      expect(
        [count(eighths, 0), count(eighths, 1), count(eighths, 2)],
        [13, 12, 75],
      );
      final one = InfoWafflePainter.cellsOf([0.4]);
      expect(count(one, 0), 40);
      expect(count(one, -1), 60);
      // Los de cada parte van juntos y en orden.
      expect(one.take(40), everyElement(0));
    },
  );

  testWidgets('la cuadrícula de cien de un porcentaje, con su cifra al lado', (
    tester,
  ) async {
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            chartKind: InfographicChartKind.waffle,
            data: [InfographicDatum(label: 'Hecho', value: 40)],
            unit: '%',
          )
          as ChartBlock,
    );
    final waffle = paintersOf<InfoWafflePainter>(tester).single;
    expect(waffle.cells.where((c) => c == 0), hasLength(40));
    expect(find.text('40 %'), findsOneWidget);
    expect(find.text('Hecho'), findsOneWidget);
  });

  testWidgets('la escala: la marca donde cae entre sus puntas, nombradas', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpChart(
      tester,
      const InfographicBlock.chart(
            title: 'Acidez',
            chartKind: InfographicChartKind.scale,
            data: [InfographicDatum(label: 'pH', value: 7)],
            minimum: 0,
            total: 14,
            minLabel: 'Ácido',
            maxLabel: 'Básico',
          )
          as ChartBlock,
    );
    final scale = paintersOf<InfoScalePainter>(tester).single;
    expect(scale.marks.single, closeTo(0.5, 1e-9));
    expect(find.text('Ácido'), findsOneWidget);
    expect(find.text('Básico'), findsOneWidget);
    expect(find.text('pH · 7'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Acidez. pH: 7 (Ácido – Básico)'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('los de F45 en lugares chicos no desbordan', (tester) async {
    const charts = [
      InfographicBlock.chart(
        chartKind: InfographicChartKind.columns,
        data: [
          InfographicDatum(label: 'Un rótulo larguísimo de verdad', value: 3),
          InfographicDatum(label: 'Otro', value: 300000),
          InfographicDatum(label: 'Tercero', value: 1),
          InfographicDatum(label: 'Cuarto', value: 9),
          InfographicDatum(label: 'Quinto', value: 99),
          InfographicDatum(label: 'Sexto', value: 7),
          InfographicDatum(label: 'Séptimo', value: 70),
          InfographicDatum(label: 'Octavo', value: 17),
        ],
      ),
      InfographicBlock.chart(
        chartKind: InfographicChartKind.rings,
        data: [
          InfographicDatum(label: 'a', value: 10),
          InfographicDatum(label: 'b', value: 20),
          InfographicDatum(label: 'c', value: 30),
          InfographicDatum(label: 'd', value: 40),
        ],
        total: 50,
      ),
      InfographicBlock.chart(
        chartKind: InfographicChartKind.waffle,
        data: [
          InfographicDatum(label: 'a', value: 25),
          InfographicDatum(label: 'b', value: 25),
          InfographicDatum(label: 'c', value: 50),
        ],
        unit: '%',
      ),
      InfographicBlock.chart(
        chartKind: InfographicChartKind.scale,
        data: [
          InfographicDatum(label: 'Uno', value: -5),
          InfographicDatum(label: 'Dos', value: 10),
          InfographicDatum(label: 'Tres', value: 40),
        ],
        minimum: -10,
        total: 40,
        unit: '°C',
      ),
    ];
    for (final size in const [Size(160, 60), Size(90, 300), Size(400, 24)]) {
      for (final chart in charts) {
        await pumpChart(tester, chart as ChartBlock, size: size);
      }
    }
  });
}
