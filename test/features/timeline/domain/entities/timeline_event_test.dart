import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

import '../../timeline_fixtures.dart';

void main() {
  group('tramo que ocupa', () {
    test('un año exacto ocupa ese año entero', () {
      final event = eventAt('a', dateOf(476));

      expect(event.from, 476.0);
      expect(event.to, 477.0);
    });

    test('un año a.C. cruza el cero sin saltos: 44 a.C. es el -43', () {
      final event = eventAt('a', dateOf(44, bce: true));

      expect(event.from, -43.0);
      expect(event.to, -42.0);
    });

    test('un siglo ocupa cien años seguidos', () {
      final event = eventAt('a', dateOf(1, precision: DatePrecision.century));

      expect(event.from, 1.0);
      expect(event.to, 101.0);
    });

    test('una década ocupa diez', () {
      final event = eventAt('a', dateOf(1920, precision: DatePrecision.decade));

      expect(event.to - event.from, 10.0);
    });

    test('un día es un tramo angosto pero positivo, dentro de su año', () {
      final event = eventAt(
        'a',
        const HistoricalDate(
          year: 1969,
          precision: DatePrecision.day,
          month: 7,
          day: 20,
        ),
      );

      expect(event.to, greaterThan(event.from));
      expect(event.to - event.from, closeTo(1 / 365, 1e-9));
      expect(event.from, greaterThan(1969.0));
      expect(event.to, lessThan(1970.0));
    });

    test('un mes termina donde empieza el siguiente', () {
      final march = eventAt(
        'a',
        const HistoricalDate(
          year: 2024,
          precision: DatePrecision.month,
          month: 3,
        ),
      );

      expect(march.from, axisStartOfMonth(2024, 3));
      expect(march.to, axisStartOfMonth(2024, 4));
    });
  });

  group('imprecisión', () {
    test('un año exacto no tiene borde difuso', () {
      final event = eventAt('a', dateOf(476));

      expect(event.fuzz, 0);
      expect(event.reachFrom, event.from);
      expect(event.reachTo, event.to);
    });

    test('circa corre cada extremo la mitad del tramo', () {
      final event = eventAt('a', dateOf(476, circa: true));

      expect(event.fuzz, 0.5);
      expect(event.reachFrom, 475.5);
      expect(event.reachTo, 477.5);
    });

    test('circa de un siglo corre cincuenta años por lado', () {
      final event = eventAt(
        'a',
        dateOf(200, circa: true, precision: DatePrecision.century),
      );

      expect(event.fuzz, 50.0);
      expect(event.reachFrom, 150.0);
      expect(event.reachTo, 350.0);
    });

    test('década y siglo son períodos; año, mes y día no', () {
      for (final precision in DatePrecision.values) {
        final event = eventAt(
          'a',
          HistoricalDate(year: 1920, precision: precision, month: 1, day: 1),
        );

        expect(
          event.isPeriod,
          precision == DatePrecision.decade ||
              precision == DatePrecision.century,
          reason: precision.name,
        );
      }
    });
  });

  test('dos eventos del mismo elemento con fechas distintas son distintos', () {
    final founding = eventAt('roma', dateOf(753, bce: true));
    final fall = eventAt('roma', dateOf(476));

    expect(founding, isNot(fall));
    expect(founding.itemId, fall.itemId);
  });
}
