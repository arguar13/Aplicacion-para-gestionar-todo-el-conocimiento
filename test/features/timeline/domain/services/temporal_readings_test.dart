import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/services/temporal_readings.dart';

/// Las reglas de qué es una fecha válida (F40), compartidas por el detector y
/// el analizador estricto.
void main() {
  group('readYear', () {
    test('un año de la era común o a.C.', () {
      expect(
        readYear(1859),
        const HistoricalDate(year: 1859, precision: DatePrecision.year),
      );
      expect(
        readYear(44, bce: true, circa: true),
        const HistoricalDate(
          year: 44,
          precision: DatePrecision.year,
          isBce: true,
          isCirca: true,
        ),
      );
    });

    test('no hay año 0, ni negativo, ni de cinco cifras', () {
      expect(readYear(0), isNull);
      expect(readYear(0, bce: true), isNull);
      expect(readYear(-5), isNull);
      expect(readYear(kMaxReadYear + 1), isNull);
      expect(readYear(kMaxReadYear), isNotNull);
      expect(readYear(1), isNotNull);
    });
  });

  group('readDate', () {
    test('un mes y un día', () {
      final month = readDate(1809, month: 2)!;
      expect(month.precision, DatePrecision.month);
      expect(month.month, 2);
      expect(month.day, isNull);

      final day = readDate(1809, month: 2, day: 12)!;
      expect(day.precision, DatePrecision.day);
      expect(day.day, 12);
    });

    test('conserva la era y lo aproximado', () {
      final date = readDate(44, month: 3, day: 15, bce: true, circa: true)!;
      expect(date.isBce, isTrue);
      expect(date.isCirca, isTrue);
    });

    test('un mes que no existe', () {
      expect(readDate(1809, month: 0), isNull);
      expect(readDate(1809, month: 13), isNull);
      expect(readDate(1809, month: -1), isNull);
      expect(readDate(1809, month: 12), isNotNull);
      expect(readDate(1809, month: 1), isNotNull);
    });

    test('un día que no existe', () {
      expect(readDate(1809, month: 1, day: 0), isNull);
      expect(readDate(1809, month: 1, day: 32), isNull);
      expect(readDate(1809, month: 4, day: 31), isNull);
      expect(readDate(1809, month: 4, day: 30), isNotNull);
      expect(readDate(1809, month: 2, day: 29), isNull);
      expect(readDate(1809, month: 2, day: 28), isNotNull);
    });

    test('el 29 de febrero, según el año bisiesto', () {
      expect(readDate(1808, month: 2, day: 29), isNotNull);
      expect(readDate(2000, month: 2, day: 29), isNotNull);
      expect(readDate(1900, month: 2, day: 29), isNull);
      expect(readDate(2100, month: 2, day: 29), isNull);
    });

    test('en a.C. el año bisiesto es el astronómico', () {
      // 45 a.C. es el año astronómico −44, bisiesto; 44 a.C. no.
      expect(readDate(45, month: 2, day: 29, bce: true), isNotNull);
      expect(readDate(44, month: 2, day: 29, bce: true), isNull);
      expect(readDate(1, month: 2, day: 29, bce: true), isNotNull);
    });

    test('un año que no existe', () {
      expect(readDate(0, month: 1), isNull);
      expect(readDate(0, month: 1, day: 1, bce: true), isNull);
      expect(readDate(kMaxReadYear + 1, month: 1), isNull);
    });
  });

  group('readCentury', () {
    test('el año de un siglo es su primer año', () {
      expect(readCentury(19)!.year, 1801);
      expect(readCentury(1)!.year, 1);
      expect(readCentury(21)!.year, 2001);
      expect(readCentury(5, bce: true)!.year, 500);
      expect(readCentury(1, bce: true)!.year, 100);
      expect(readCentury(19)!.precision, DatePrecision.century);
    });

    test('el siglo V a.C. va de 500 a 401 a.C., el XIX de 1801 a 1900', () {
      final fifthBce = readCentury(5, bce: true)!;
      expect(fifthBce.rangeStart.year, -499);
      expect(fifthBce.rangeEnd.year, -400);
      final nineteenth = readCentury(19)!;
      expect(nineteenth.rangeStart.year, 1801);
      expect(nineteenth.rangeEnd.year, 1900);
    });

    test('no hay siglo 0, negativo ni mayor al XL', () {
      expect(readCentury(0), isNull);
      expect(readCentury(-1), isNull);
      expect(readCentury(kMaxReadCentury), isNotNull);
      expect(readCentury(kMaxReadCentury + 1), isNull);
      expect(kMaxReadCentury, 40);
    });

    test('conserva lo aproximado', () {
      expect(readCentury(15, circa: true)!.isCirca, isTrue);
    });
  });

  group('readDecade', () {
    test('la década empieza en un año terminado en cero', () {
      expect(readDecade(1920)!.year, 1920);
      expect(readDecade(1920)!.precision, DatePrecision.decade);
      expect(readDecade(10), isNotNull);
      expect(readDecade(2990), isNotNull);
      expect(readDecade(1920, circa: true)!.isCirca, isTrue);
    });

    test('un año que no empieza una década no lo es', () {
      expect(readDecade(1925), isNull);
      expect(readDecade(1921), isNull);
      expect(readDecade(5), isNull);
      expect(readDecade(0), isNull);
      expect(readDecade(-10), isNull);
      expect(readDecade(10000), isNull);
    });
  });

  group('isBceMarker', () {
    test('antes de Cristo', () {
      for (final marker in [
        'a.C.',
        'a.C',
        'a. C.',
        'A.C.',
        'aC',
        'a. de C.',
        'a. J.C.',
        'BC',
        'B.C.',
        'BCE',
        'B.C.E.',
        'bc',
        'antes de Cristo',
        'Antes de Cristo',
        'before Christ',
        'Before Christ',
      ]) {
        expect(isBceMarker(marker), isTrue, reason: marker);
      }
    });

    test('después de Cristo', () {
      for (final marker in [
        'd.C.',
        'd. C.',
        'D.C.',
        'dC',
        'd. de C.',
        'd. J.C.',
        'AD',
        'A.D.',
        'CE',
        'C.E.',
        'ad',
        'después de Cristo',
        'Despues de Cristo',
      ]) {
        expect(isBceMarker(marker), isFalse, reason: marker);
      }
    });

    test('otra cosa no es una era', () {
      for (final marker in ['', 'x', 'a', 'C', 'd', 'año', 'Cristo']) {
        expect(isBceMarker(marker), isNull, reason: marker);
      }
    });
  });

  group('nombres', () {
    test('los meses en castellano y en inglés', () {
      const names = [
        ('enero', 'January'),
        ('febrero', 'February'),
        ('marzo', 'March'),
        ('abril', 'April'),
        ('mayo', 'May'),
        ('junio', 'June'),
        ('julio', 'July'),
        ('agosto', 'August'),
        ('septiembre', 'September'),
        ('octubre', 'October'),
        ('noviembre', 'November'),
        ('diciembre', 'December'),
      ];
      for (final (i, (es, en)) in names.indexed) {
        expect(monthOfName(es), i + 1, reason: es);
        expect(monthOfName(en), i + 1, reason: en);
        expect(monthOfName(es.toUpperCase()), i + 1);
      }
      expect(monthOfName('setiembre'), 9);
      expect(monthOfName('mes'), isNull);
      expect(monthOfName(''), isNull);
    });

    test('el patrón de meses acepta la primera letra en mayúscula', () {
      final pattern = RegExp('^$monthNamesPattern\$');
      for (final text in [
        'enero',
        'Enero',
        'September',
        'setiembre',
        'May',
        'mayo',
      ]) {
        expect(pattern.hasMatch(text), isTrue, reason: text);
      }
      for (final text in ['ENERO', 'Ene', 'mayor', 'enero ']) {
        expect(pattern.hasMatch(text), isFalse, reason: text);
      }
    });

    test('«mayo» no se corta en «may»', () {
      final m = RegExp(monthNamesPattern).firstMatch('mayo de 1809')!;
      expect(m.group(0), 'mayo');
    });

    test('los siglos en palabras', () {
      expect(centuryOfOrdinalWord('first'), 1);
      expect(centuryOfOrdinalWord('Fifth'), 5);
      expect(centuryOfOrdinalWord('nineteenth'), 19);
      expect(centuryOfOrdinalWord('twentieth'), 20);
      expect(centuryOfOrdinalWord('twenty-first'), 21);
      expect(centuryOfOrdinalWord('twenty-second'), isNull);
      expect(centuryOfOrdinalWord('zeroth'), isNull);
      final pattern = RegExp('^$ordinalWordsPattern\$');
      expect(pattern.hasMatch('twenty-first'), isTrue);
      expect(pattern.hasMatch('Twenty-first'), isTrue);
      expect(pattern.hasMatch('twentieth'), isTrue);
      expect(pattern.hasMatch('twenty'), isFalse);
    });

    test(
      'caseFlexibleAlternation acepta mayúscula solo en la primera letra',
      () {
        final pattern = RegExp(
          '^${caseFlexibleAlternation(['abc', 'abcd'])}\$',
        );
        expect(pattern.hasMatch('abc'), isTrue);
        expect(pattern.hasMatch('Abc'), isTrue);
        expect(pattern.hasMatch('abcd'), isTrue);
        expect(pattern.hasMatch('ABC'), isFalse);
      },
    );
  });

  test('la era se reconoce con sus puntos y sin ellos en un texto', () {
    final era = RegExp('^$eraMarkerPattern\$');
    for (final marker in [
      'a.C.',
      'a.C',
      'a. C.',
      'a. de C.',
      'a. J.C.',
      'A.C.',
      'aC',
      'd.C.',
      'dC',
      'BC',
      'B.C.',
      'BCE',
      'B.C.E.',
      'AD',
      'A.D.',
      'CE',
      'C.E.',
      'antes de Cristo',
      'después de Cristo',
      'Before Christ',
    ]) {
      expect(era.hasMatch(marker), isTrue, reason: marker);
    }
    for (final text in ['BC.', 'a C', 'a', 'ad', 'bc', 'B.C', 'AC', 'DC']) {
      expect(era.hasMatch(text), isFalse, reason: text);
    }
  });
}
