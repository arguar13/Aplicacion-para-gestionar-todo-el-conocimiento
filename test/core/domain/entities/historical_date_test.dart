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

  group('fromStored', () {
    test('conserva mes y día cuando la precisión los usa', () {
      final date = HistoricalDate.fromStored(
        astronomicalYear: 1969,
        precision: DatePrecision.day,
        month: 7,
        day: 20,
      );

      expect(
        date,
        const HistoricalDate(
          year: 1969,
          precision: DatePrecision.day,
          month: 7,
          day: 20,
        ),
      );
    });

    test(
      'descarta el 1 que la base guarda para lo que la precisión no usa',
      () {
        // La base guarda month/day = 1 en el extremo inferior de un año, una
        // década o un siglo. Devolverlos haría que la fecha leída no fuera la
        // que se escribió.
        for (final precision in [
          DatePrecision.year,
          DatePrecision.decade,
          DatePrecision.century,
        ]) {
          final date = HistoricalDate.fromStored(
            astronomicalYear: 1920,
            precision: precision,
            month: 1,
            day: 1,
          );

          expect(date.month, isNull, reason: precision.name);
          expect(date.day, isNull, reason: precision.name);
        }
      },
    );

    test('con precisión de mes descarta el día', () {
      final date = HistoricalDate.fromStored(
        astronomicalYear: -43,
        precision: DatePrecision.month,
        month: 3,
        day: 1,
      );

      expect(date.month, 3);
      expect(date.day, isNull);
      expect(date.isBce, isTrue);
      expect(date.year, 44);
    });

    test('circa ausente es falso', () {
      final date = HistoricalDate.fromStored(
        astronomicalYear: 476,
        precision: DatePrecision.year,
      );

      expect(date.isCirca, isFalse);
    });

    test('es el inverso de lo que se guarda: rangeStart y astronomicalYear '
        'vuelven a la misma fecha', () {
      const original = HistoricalDate(
        year: 340,
        precision: DatePrecision.month,
        month: 3,
        isBce: true,
        isCirca: true,
      );
      final start = original.rangeStart;

      final restored = HistoricalDate.fromStored(
        astronomicalYear: start.year,
        precision: original.precision,
        month: start.month,
        day: start.day,
        isCirca: true,
      );

      expect(restored, original);
    });
  });

  group('calendario', () {
    test('años bisiestos, también antes de 1 d.C.', () {
      expect(isLeapYear(2024), isTrue);
      expect(isLeapYear(1900), isFalse);
      expect(isLeapYear(2000), isTrue);
      // El año astronómico 0 (1 a.C.) es bisiesto en el calendario
      // proléptico; -4 (5 a.C.) también; -1 (2 a.C.) no.
      expect(isLeapYear(0), isTrue);
      expect(isLeapYear(-4), isTrue);
      expect(isLeapYear(-1), isFalse);
    });

    test('días del mes', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2023, 2), 28);
      expect(daysInMonth(2023, 4), 30);
      expect(daysInMonth(2023, 12), 31);
    });
  });
}
