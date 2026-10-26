import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_input.dart';

/// Lo que se puede guardar como hecho fechado (F40): las mismas invariantes que
/// después hace cumplir la base, dichas antes y para quien las escribió.
void main() {
  HistoricalDate year(int y, {bool bce = false}) =>
      HistoricalDate(year: y, precision: DatePrecision.year, isBce: bce);

  HistoricalDate month(int y, int m) =>
      HistoricalDate(year: y, precision: DatePrecision.month, month: m);

  HistoricalDate day(int y, int m, int d) =>
      HistoricalDate(year: y, precision: DatePrecision.day, month: m, day: d);

  group('el título', () {
    test('no puede estar vacío ni ser solo espacios', () {
      expect(DatedEventInput(title: '', date: year(1809)).problem, isNotNull);
      expect(
        DatedEventInput(title: ' \n', date: year(1809)).problem,
        isNotNull,
      );
      expect(DatedEventInput(title: 'Nace', date: year(1809)).problem, isNull);
    });
  });

  group('la fecha', () {
    test('un año, un mes o un día que existen están bien', () {
      for (final date in [
        year(1),
        year(44, bce: true),
        month(1914, 8),
        day(2024, 2, 29),
        const HistoricalDate(year: 1920, precision: DatePrecision.decade),
        const HistoricalDate(year: 100, precision: DatePrecision.century),
      ]) {
        expect(DatedEventInput(title: 'x', date: date).problem, isNull);
      }
    });

    test('lo que no existe se rechaza', () {
      for (final date in [
        const HistoricalDate(year: 0, precision: DatePrecision.year),
        const HistoricalDate(year: 1900, precision: DatePrecision.month),
        month(1900, 13),
        month(1900, 0),
        const HistoricalDate(
          year: 1900,
          precision: DatePrecision.day,
          month: 1,
        ),
        day(1900, 2, 29),
        day(2023, 4, 31),
        day(2023, 4, 0),
      ]) {
        expect(
          DatedEventInput(title: 'x', date: date).problem,
          isNotNull,
          reason: '$date',
        );
      }
    });

    test('el 29 de febrero vale en un año bisiesto, también a.C.', () {
      expect(
        DatedEventInput(title: 'x', date: day(2000, 2, 29)).problem,
        isNull,
      );
      // 45 a.C. es el año astronómico -44: bisiesto.
      expect(
        const DatedEventInput(
          title: 'x',
          date: HistoricalDate(
            year: 45,
            precision: DatePrecision.day,
            month: 2,
            day: 29,
            isBce: true,
          ),
        ).problem,
        isNull,
      );
    });
  });

  group('el fin', () {
    test('no puede terminar antes de que termine el inicio', () {
      expect(
        DatedEventInput(title: 'x', date: year(1914), end: year(1918)).problem,
        isNull,
      );
      expect(
        DatedEventInput(title: 'x', date: year(1918), end: year(1914)).problem,
        isNotNull,
      );
      expect(
        DatedEventInput(
          title: 'x',
          date: year(44, bce: true),
          end: year(50, bce: true),
        ).problem,
        isNotNull,
      );
      // Cruza el cero: de 10 a.C. a 10 d.C.
      expect(
        DatedEventInput(
          title: 'x',
          date: year(10, bce: true),
          end: year(10),
        ).problem,
        isNull,
      );
    });

    test('puede terminar en la misma fecha o dentro del mismo año', () {
      expect(
        DatedEventInput(title: 'x', date: year(1914), end: year(1914)).problem,
        isNull,
      );
      expect(
        DatedEventInput(
          title: 'x',
          date: month(1914, 8),
          end: year(1914),
        ).problem,
        isNull,
      );
      expect(
        DatedEventInput(
          title: 'x',
          date: year(1914),
          end: month(1914, 3),
        ).problem,
        isNotNull,
      );
    });

    test('un fin que no es una fecha se rechaza', () {
      expect(
        DatedEventInput(
          title: 'x',
          date: year(1914),
          end: month(1918, 14),
        ).problem,
        isNotNull,
      );
    });
  });

  group('la cita', () {
    DatedEventInput cited({
      String? rendition = 'texto',
      int? start = 3,
      int? end = 9,
      String? excerpt = 'Darwin',
    }) => DatedEventInput(
      title: 'x',
      date: year(1809),
      renditionId: rendition,
      startOffset: start,
      endOffset: end,
      excerpt: excerpt,
    );

    test('con su texto, su tramo y su fragmento está bien', () {
      expect(cited().problem, isNull);
    });

    test('sin posición vale: solo el texto, o solo el fragmento', () {
      expect(cited(start: null, end: null).problem, isNull);
      expect(cited(rendition: null, start: null, end: null).problem, isNull);
    });

    test('la posición viene entera, es un tramo y tiene texto y fragmento', () {
      expect(cited(end: null).problem, isNotNull);
      expect(cited(start: null).problem, isNotNull);
      expect(cited(start: 5, end: 5).problem, isNotNull);
      expect(cited(start: 9, end: 3).problem, isNotNull);
      expect(cited(start: -1).problem, isNotNull);
      expect(cited(rendition: null).problem, isNotNull);
      expect(cited(excerpt: null).problem, isNotNull);
      expect(cited(excerpt: '  ').problem, isNotNull);
    });
  });
}
