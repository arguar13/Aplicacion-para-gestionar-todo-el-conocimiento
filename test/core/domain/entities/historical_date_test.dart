import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';

void main() {
  group('año astronómico', () {
    test('1 d.C. es el año astronómico 1', () {
      const date = HistoricalDate(year: 1, precision: DatePrecision.year);

      expect(date.astronomicalYear, 1);
    });

    test('1 a.C. es el año astronómico 0', () {
      const date = HistoricalDate(
        year: 1,
        precision: DatePrecision.year,
        isBce: true,
      );

      expect(date.astronomicalYear, 0);
    });

    test('44 a.C. es el año astronómico -43', () {
      const date = HistoricalDate(
        year: 44,
        precision: DatePrecision.year,
        isBce: true,
      );

      expect(date.astronomicalYear, -43);
    });

    test('fromAstronomicalYear es el inverso exacto, ida y vuelta', () {
      for (final year in [1, 0, -43, -339, 476, 2026]) {
        final date = HistoricalDate.fromAstronomicalYear(
          year,
          precision: DatePrecision.year,
        );

        expect(date.astronomicalYear, year);
      }
    });

    test('fromAstronomicalYear(-43) reconstruye 44 a.C.', () {
      final date = HistoricalDate.fromAstronomicalYear(
        -43,
        precision: DatePrecision.year,
      );

      expect(date.isBce, isTrue);
      expect(date.year, 44);
    });
  });

  group('rango según precisión', () {
    test('day: inicio y fin son el mismo día', () {
      const date = HistoricalDate(
        year: 2026,
        precision: DatePrecision.day,
        month: 3,
        day: 15,
      );

      expect(date.rangeStart, (year: 2026, month: 3, day: 15));
      expect(date.rangeEnd, (year: 2026, month: 3, day: 15));
    });

    test('month: del día 1 al último día del mes', () {
      const date = HistoricalDate(
        year: 2026,
        precision: DatePrecision.month,
        month: 2,
      );

      expect(date.rangeStart, (year: 2026, month: 2, day: 1));
      // 2026 no es bisiesto.
      expect(date.rangeEnd, (year: 2026, month: 2, day: 28));
    });

    test('month: respeta el 29 de febrero en un año bisiesto', () {
      const date = HistoricalDate(
        year: 2028,
        precision: DatePrecision.month,
        month: 2,
      );

      expect(date.rangeEnd, (year: 2028, month: 2, day: 29));
    });

    test('year: del 1/1 al 31/12 del mismo año', () {
      const date = HistoricalDate(year: 1920, precision: DatePrecision.year);

      expect(date.rangeStart, (year: 1920, month: 1, day: 1));
      expect(date.rangeEnd, (year: 1920, month: 12, day: 31));
    });

    test('decade: cubre diez años completos', () {
      const date = HistoricalDate(year: 1920, precision: DatePrecision.decade);

      expect(date.rangeStart, (year: 1920, month: 1, day: 1));
      expect(date.rangeEnd, (year: 1929, month: 12, day: 31));
    });

    test('century: cubre cien años completos', () {
      const date = HistoricalDate(year: 1900, precision: DatePrecision.century);

      expect(date.rangeStart, (year: 1900, month: 1, day: 1));
      expect(date.rangeEnd, (year: 1999, month: 12, day: 31));
    });

    test(
      'una década antes de Cristo cruza el cero sin ningún caso especial',
      () {
        // 340 a.C. → astronómico -339. Década: [-339, -330], que en
        // fechas de calendario son los años 340 a 331 a.C.
        final date = HistoricalDate.fromAstronomicalYear(
          -339,
          precision: DatePrecision.decade,
        );

        expect(date.rangeStart, (year: -339, month: 1, day: 1));
        expect(date.rangeEnd, (year: -330, month: 12, day: 31));
        expect(
          HistoricalDate.fromAstronomicalYear(
            date.rangeEnd.year,
            precision: DatePrecision.year,
          ).year,
          331,
        );
      },
    );
  });

  group('label', () {
    test('day: día, mes en palabras y año', () {
      const date = HistoricalDate(
        year: 2026,
        precision: DatePrecision.day,
        month: 3,
        day: 15,
      );

      expect(date.label, '15 de marzo de 2026');
    });

    test('month: mes en palabras y año', () {
      const date = HistoricalDate(
        year: 44,
        precision: DatePrecision.month,
        month: 7,
        isBce: true,
      );

      expect(date.label, 'julio de 44 a.C.');
    });

    test('year: el año, sin "d.C." de más', () {
      const date = HistoricalDate(year: 1969, precision: DatePrecision.year);

      expect(date.label, '1969');
    });

    test('year: "a.C." si es antes de Cristo', () {
      const date = HistoricalDate(
        year: 44,
        precision: DatePrecision.year,
        isBce: true,
      );

      expect(date.label, '44 a.C.');
    });

    test('decade: el rango de diez años que cubre', () {
      const date = HistoricalDate(year: 1920, precision: DatePrecision.decade);

      expect(date.label, '1920 – 1929');
    });

    test('century: el rango de cien años que cubre, cruzando a.C./d.C. '
        'si corresponde', () {
      final date = HistoricalDate.fromAstronomicalYear(
        -49,
        precision: DatePrecision.century,
      );

      expect(date.label, '50 a.C. – 50');
    });

    test('circa antepone "circa " al resto del label', () {
      const date = HistoricalDate(
        year: 340,
        precision: DatePrecision.year,
        isBce: true,
        isCirca: true,
      );

      expect(date.label, 'circa 340 a.C.');
    });
  });
}
