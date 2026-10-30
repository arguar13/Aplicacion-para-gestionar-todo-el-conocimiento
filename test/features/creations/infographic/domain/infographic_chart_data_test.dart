import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_chart_data.dart';

/// Las cuentas de los gráficos (F43, y los cuatro de F45): qué gráfico va,
/// cuánto mide cada dato y cómo se escribe.
void main() {
  ChartBlock chart(
    List<(String, double)> data, {
    InfographicChartKind? kind,
    String unit = '',
    double? total,
    double? minimum,
    String minLabel = '',
    String maxLabel = '',
  }) =>
      InfographicBlock.chart(
            chartKind: kind,
            unit: unit,
            total: total,
            minimum: minimum,
            minLabel: minLabel,
            maxLabel: maxLabel,
            data: [
              for (final (label, value) in data)
                InfographicDatum(label: label, value: value),
            ],
          )
          as ChartBlock;

  group('qué gráfico va', () {
    test('si la IA no lo dice, el que piden los datos', () {
      expect(
        InfographicChartData.kindOf(chart([('a', 7)], total: 10)),
        InfographicChartKind.pictogram,
      );
      expect(
        InfographicChartData.kindOf(chart([('a', 40)], unit: '%')),
        InfographicChartKind.ring,
      );
      expect(
        InfographicChartData.kindOf(chart([('a', 3)], total: 40)),
        InfographicChartKind.progress,
      );
      expect(
        InfographicChartData.kindOf(chart([('a', 55), ('b', 45)], unit: '%')),
        InfographicChartKind.ring,
      );
      expect(
        InfographicChartData.kindOf(chart([('a', 15), ('b', 3), ('c', 22)])),
        InfographicChartKind.bars,
      );
    });

    test('lo que pidió la IA, salvo un pictograma que no se puede contar', () {
      expect(
        InfographicChartData.kindOf(
          chart([('a', 1), ('b', 2)], kind: InfographicChartKind.ring),
        ),
        InfographicChartKind.ring,
      );
      expect(
        InfographicChartData.kindOf(
          chart([('a', 3000000)], kind: InfographicChartKind.pictogram),
        ),
        InfographicChartKind.progress,
      );
      expect(
        InfographicChartData.kindOf(
          chart([
            for (var i = 0; i < 5; i++) ('d$i', 2),
          ], kind: InfographicChartKind.pictogram),
        ),
        InfographicChartKind.bars,
      );
    });
  });

  group('cuánto mide cada dato', () {
    test('las barras, contra la mayor', () {
      final points = InfographicChartData.points(
        chart([('a', 15), ('b', 3), ('c', 30)]),
      );
      expect(points.map((p) => p.fraction), [0.5, 0.1, 1]);
    });

    test('el anillo: un dato contra su total; varios, su parte', () {
      expect(
        InfographicChartData.points(
          chart([('a', 40)], unit: '%'),
        ).single.fraction,
        closeTo(0.4, 1e-9),
      );
      final parts = InfographicChartData.points(
        chart([('a', 1), ('b', 3)], kind: InfographicChartKind.ring),
      );
      expect(parts.map((p) => p.fraction), [0.25, 0.75]);
    });

    test('el avance, contra el total; un negativo no resta', () {
      expect(
        InfographicChartData.points(
          chart([('a', 3)], total: 40),
        ).single.fraction,
        closeTo(3 / 40, 1e-9),
      );
      final points = InfographicChartData.points(
        chart([('a', -5), ('b', 10)], kind: InfographicChartKind.bars),
      );
      expect(points.first.fraction, 0);
      // Más que el total no se pasa del entero.
      expect(
        InfographicChartData.points(
          chart([('a', 50)], kind: InfographicChartKind.progress, total: 40),
        ).single.fraction,
        1,
      );
    });

    test('el pictograma cuenta hasta su total, o hasta diez', () {
      expect(InfographicChartData.pictogramTotal(chart([('a', 7)])), 10);
      expect(
        InfographicChartData.pictogramTotal(chart([('a', 7)], total: 20)),
        20,
      );
      expect(InfographicChartData.pictogramTotal(chart([('a', 15)])), 15);
      expect(InfographicChartData.pictogramTotal(chart([('a', 25)])), isNull);
      expect(
        InfographicChartData.pictogramTotal(chart([('a', 12)], total: 10)),
        isNull,
      );
    });
  });

  test('cómo se escribe: lo de la IA, o el número con su unidad', () {
    expect(
      InfographicChartData.textOf(
        const InfographicDatum(label: 'a', value: 2.5, display: '2,5 M'),
        'km',
      ),
      '2,5 M',
    );
    expect(
      InfographicChartData.textOf(
        const InfographicDatum(label: 'a', value: 1500),
        'años',
      ),
      '1.500 años',
    );
    expect(
      InfographicChartData.textOf(
        const InfographicDatum(label: 'a', value: 40),
        '%',
      ),
      '40 %',
    );
  });

  test('lo que dice en palabras, para el lector de pantalla', () {
    const block = ChartBlock(
      title: 'Capítulos',
      data: [
        InfographicDatum(label: 'Egipto', value: 15),
        InfographicDatum(label: 'Sinaí', value: 22),
      ],
    );
    expect(
      InfographicChartData.describe(block),
      'Capítulos. Egipto: 15; Sinaí: 22',
    );
  });

  group('los de F45', () {
    InfographicChartKind kind(ChartBlock c) => InfographicChartData.kindOf(c);

    test('van si los pide la IA y los datos los sostienen', () {
      expect(
        kind(chart([('a', 1), ('b', 2)], kind: InfographicChartKind.columns)),
        InfographicChartKind.columns,
      );
      expect(
        kind(chart([('a', 40)], unit: '%', kind: InfographicChartKind.rings)),
        InfographicChartKind.rings,
      );
      expect(
        kind(chart([('a', 40)], unit: '%', kind: InfographicChartKind.waffle)),
        InfographicChartKind.waffle,
      );
      expect(
        kind(chart([('a', 7)], total: 14, kind: InfographicChartKind.scale)),
        InfographicChartKind.scale,
      );
    });

    test('si no los sostienen, el de F43 que corresponde', () {
      // Una columna sola no compara nada.
      expect(
        kind(chart([('a', 1)], kind: InfographicChartKind.columns)),
        InfographicChartKind.progress,
      );
      // Cinco vueltas no se distinguen.
      expect(
        kind(
          chart([
            for (var i = 0; i < 5; i++) ('d$i', 10.0 * i),
          ], kind: InfographicChartKind.rings),
        ),
        InfographicChartKind.bars,
      );
      // Una cuadrícula de cien sin un todo, o con partes que lo pasan.
      expect(
        kind(chart([('a', 40)], kind: InfographicChartKind.waffle)),
        InfographicChartKind.progress,
      );
      expect(
        kind(
          chart(
            [('a', 70), ('b', 60)],
            unit: '%',
            kind: InfographicChartKind.waffle,
          ),
        ),
        InfographicChartKind.bars,
      );
      // Una escala sin máximo, o con más marcas de las que entran.
      expect(
        kind(chart([('a', 7)], kind: InfographicChartKind.scale)),
        InfographicChartKind.progress,
      );
      expect(
        kind(
          chart(
            [for (var i = 0; i < 4; i++) ('d$i', 1.0 * i)],
            total: 10,
            kind: InfographicChartKind.scale,
          ),
        ),
        InfographicChartKind.bars,
      );
    });

    test('la escala va sola si trae su mínimo', () {
      expect(
        kind(chart([('pH', 7)], total: 14, minimum: 0)),
        InfographicChartKind.scale,
      );
      // Sin mínimo, lo de siempre: «7 de 14» se cuenta en un pictograma.
      expect(
        kind(chart([('pH', 7)], total: 14)),
        InfographicChartKind.pictogram,
      );
    });

    test('cuánto mide cada dato', () {
      List<double> fractions(ChartBlock c) => [
        for (final p in InfographicChartData.points(c)) p.fraction,
      ];
      // Columnas: contra la mayor.
      expect(
        fractions(
          chart([('a', 10), ('b', 40)], kind: InfographicChartKind.columns),
        ),
        [0.25, 1],
      );
      // Anillos: contra el total, o 100 en porcentajes.
      expect(
        fractions(
          chart(
            [('a', 80), ('b', 20)],
            unit: '%',
            kind: InfographicChartKind.rings,
          ),
        ),
        [0.8, 0.2],
      );
      // La cuadrícula: partes de un todo que suman la suya.
      expect(
        fractions(
          chart([('a', 3), ('b', 1)], kind: InfographicChartKind.waffle),
        ),
        [0.75, 0.25],
      );
      // La escala: dónde cae entre sus puntas, también con negativos.
      expect(
        fractions(
          chart(
            [('frío', -10), ('tibio', 15), ('calor', 60)],
            minimum: -10,
            total: 40,
            kind: InfographicChartKind.scale,
          ),
        ),
        [0, 0.5, 1],
      );
    });

    test('la escala se lee con sus puntas: sus nombres, o sus números', () {
      expect(
        InfographicChartData.describe(
          chart(
            [('pH', 7)],
            total: 14,
            minimum: 0,
            minLabel: 'Ácido',
            maxLabel: 'Básico',
          ),
        ),
        'pH: 7 (Ácido – Básico)',
      );
      expect(
        InfographicChartData.describe(
          chart([('Hoy', 18)], total: 40, minimum: -10, unit: '°C'),
        ),
        'Hoy: 18 °C (-10 °C – 40 °C)',
      );
    });
  });
}
