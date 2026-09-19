import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/timeline/domain/services/axis_scale.dart';

void main() {
  List<int> years(AxisScale scale) => scale.ticks.map((t) => t.year).toList();

  group('ventana inválida', () {
    test('sin ancho, al revés o infinita no da marcas', () {
      for (final (from, to) in [
        (10.0, 10.0),
        (20.0, 10.0),
        (double.nan, 10.0),
        (0.0, double.infinity),
      ]) {
        expect(axisScale(from: from, to: to).ticks, isEmpty);
      }
    });
  });

  group('años', () {
    test('elige un paso de la serie 1, 2, 5 × 10ⁿ', () {
      // 1.000 años con ~8 marcas piden 125 por marca: el paso que sigue es 200.
      final scale = axisScale(from: 1000, to: 2000);

      expect(scale.unit, AxisUnit.years);
      expect(scale.step, 200);
      expect(years(scale), [1000, 1200, 1400, 1600, 1800, 2000]);
    });

    test('todo paso es 1, 2 o 5 por una potencia de diez', () {
      for (final span in [9, 20, 75, 160, 900, 4000, 30000, 1000000]) {
        final scale = axisScale(from: 100, to: 100 + span.toDouble());

        expect(scale.unit, AxisUnit.years, reason: 'span $span');
        var step = scale.step;
        while (step >= 10) {
          expect(step % 10, 0, reason: 'span $span, paso ${scale.step}');
          step ~/= 10;
        }
        expect([1, 2, 5], contains(step), reason: 'span $span');
      }
    });

    test('cruzando el cero, las marcas de a.C. y d.C. no dejan hueco de dos '
        'pasos', () {
      final scale = axisScale(from: -250, to: 250);

      expect(scale.step, 100);
      // "200 a.C." y "100 a.C." caen en -199 y -99 (el año N a.C. empieza en
      // 1 - N); después el "1 d.C." de la era y las de d.C.
      expect(years(scale), [-199, -99, 1, 100, 200]);
    });

    test('la marca de la era aparece si el paso es mayor que un año', () {
      final scale = axisScale(from: -50, to: 50);

      expect(years(scale), contains(1));
      expect(scale.step, greaterThan(1));
    });

    test('con paso de un año, cada año tiene su marca, sin repetir la era', () {
      final scale = axisScale(from: -2.5, to: 3.5);

      expect(scale.step, 1);
      expect(years(scale), [-2, -1, 0, 1, 2, 3]);
    });

    test('las marcas de a.C. son el comienzo de ese año: 100 a.C. empieza '
        'en el -99', () {
      final scale = axisScale(from: -300, to: -50);

      // El año astronómico -99 es 100 a.C.
      expect(years(scale), contains(-99));
      expect(years(scale), isNot(contains(-100)));
    });

    test('la posición de cada marca es su año', () {
      for (final tick in axisScale(from: -400, to: 400).ticks) {
        expect(tick.position, tick.year.toDouble());
        expect(tick.month, 1);
      }
    });

    test('las marcas van de izquierda a derecha y dentro de la ventana', () {
      final random = Random(5);
      for (var i = 0; i < 200; i++) {
        final from = -5000 + random.nextDouble() * 7000;
        final to = from + 0.5 + random.nextDouble() * 4000;

        final ticks = axisScale(from: from, to: to).ticks;

        for (var t = 0; t < ticks.length; t++) {
          expect(ticks[t].position, inInclusiveRange(from, to));
          if (t > 0) {
            expect(ticks[t].position, greaterThan(ticks[t - 1].position));
          }
        }
      }
    });

    test('nunca da más marcas de las pedidas más una', () {
      final random = Random(6);
      for (var i = 0; i < 300; i++) {
        final from = -100000 + random.nextDouble() * 200000;
        final to =
            from + 0.05 + random.nextDouble() * pow(10, random.nextInt(6));

        final scale = axisScale(from: from, to: to);

        // Ocho marcas del paso, una más por la era.
        expect(scale.ticks.length, lessThanOrEqualTo(10));
      }
    });

    test('un rango enorme sigue dando pocas marcas', () {
      final scale = axisScale(from: -1000000, to: 1000000);

      expect(scale.ticks.length, lessThanOrEqualTo(10));
      expect(scale.step, 500000);
    });
  });

  group('meses', () {
    test('debajo de un año por marca se pasa a meses', () {
      // Medio año con ~8 marcas: una por mes.
      final scale = axisScale(from: 1969, to: 1969.5);

      expect(scale.unit, AxisUnit.months);
      expect(scale.step, 1);
      // De enero a julio: agosto empieza pasado el medio año.
      expect(scale.ticks.map((t) => t.month), [1, 2, 3, 4, 5, 6, 7]);
      expect(scale.ticks.every((t) => t.year == 1969), isTrue);
    });

    test('la primera marca de un mes cae en el comienzo real del mes', () {
      final scale = axisScale(from: 2024, to: 2024.3);

      final march = scale.ticks.firstWhere((t) => t.month == 3);
      // Enero y febrero de 2024 suman 60 de los 366 días.
      expect(march.position, closeTo(2024 + 60 / 366, 1e-12));
    });

    test('con meses más espaciados se saltan meses', () {
      final scale = axisScale(from: 2000, to: 2004);

      // Cuatro años con ~8 marcas piden medio año: de enero a julio.
      expect(scale.unit, AxisUnit.months);
      expect(scale.step, 6);
      expect(scale.ticks.map((t) => t.month).toSet(), {1, 7});
    });

    test('una ventana que cruza el fin de año sigue el orden', () {
      final scale = axisScale(from: 1999.9, to: 2000.3);

      final positions = scale.ticks.map((t) => t.position).toList();
      expect([...positions]..sort(), positions);
      expect(scale.ticks.first.year, 1999);
      expect(scale.ticks.first.month, 12);
    });

    test('el paso en meses es 1, 2, 3 o 6', () {
      for (final span in [0.05, 0.2, 0.5, 1, 3, 4]) {
        final scale = axisScale(from: 1900, to: 1900 + span.toDouble());

        expect(scale.unit, AxisUnit.months, reason: 'span $span');
        expect([1, 2, 3, 6], contains(scale.step), reason: 'span $span');
      }
    });

    test('con casi un año por marca el paso que sigue es el año entero', () {
      // 7,6 años con 8 marcas piden 0,95 años por marca: ni 6 meses alcanzan.
      final scale = axisScale(from: 1900, to: 1907.6);

      expect(scale.unit, AxisUnit.years);
      expect(scale.step, 1);
    });

    test('también en a.C.', () {
      final scale = axisScale(from: -44, to: -43.6);

      expect(scale.unit, AxisUnit.months);
      expect(scale.ticks.every((t) => t.year == -44 || t.year == -43), isTrue);
    });
  });
}
