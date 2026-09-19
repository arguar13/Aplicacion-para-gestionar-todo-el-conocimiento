import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';

void main() {
  DatePoint day(int year, int month, int day) =>
      (year: year, month: month, day: day);

  group('posición de un día', () {
    test(
      '1 de enero empieza en el año entero, 1 d.C. en 1.0 y 1 a.C. en 0.0',
      () {
        expect(axisStart(day(1, 1, 1)), 1.0);
        expect(axisStart(day(0, 1, 1)), 0.0);
        expect(axisStart(day(-43, 1, 1)), -43.0);
      },
    );

    test('un día termina donde empieza el siguiente', () {
      expect(axisEnd(day(2026, 3, 14)), axisStart(day(2026, 3, 15)));
    });

    test('el último día del año termina donde empieza el año siguiente, '
        'bisiesto o no', () {
      for (final year in [2023, 2024, 1900, 2000, 1, 0, -1, -4, -43]) {
        expect(
          axisEnd(day(year, 12, 31)),
          (year + 1).toDouble(),
          reason: 'año $year',
        );
      }
    });

    test('el fin de febrero da paso a marzo sin hueco, en bisiesto y en no '
        'bisiesto', () {
      expect(axisEnd(day(2024, 2, 29)), axisStart(day(2024, 3, 1)));
      expect(axisEnd(day(2023, 2, 28)), axisStart(day(2023, 3, 1)));
    });

    test('un día siempre ocupa un tramo positivo', () {
      for (final year in [-500, -1, 0, 1, 1969, 2024]) {
        for (var month = 1; month <= 12; month++) {
          final point = day(year, month, 1);
          expect(axisEnd(point), greaterThan(axisStart(point)));
        }
      }
    });
  });

  group('sin salto en el cero', () {
    test('1 a.C. y 1 d.C. son años consecutivos: uno termina donde empieza el '
        'otro', () {
      // 1 a.C. es el astronómico 0 y 1 d.C. el 1: no hay año cero en el
      // calendario, pero el eje no tiene ningún hueco ahí.
      expect(axisEnd(day(0, 12, 31)), axisStart(day(1, 1, 1)));
    });

    test('las posiciones crecen con el tiempo cruzando el cero', () {
      final positions = [
        for (final year in [-100, -43, -1, 0, 1, 2, 100])
          axisStart(day(year, 1, 1)),
      ];

      expect([...positions]..sort(), positions);
    });
  });

  group('inicio de mes', () {
    test('enero de un año es el año entero', () {
      expect(axisStartOfMonth(1969, 1), 1969.0);
    });

    test('coincide con el primer día del mes', () {
      expect(axisStartOfMonth(2024, 3), axisStart(day(2024, 3, 1)));
    });
  });
}
