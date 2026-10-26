import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/dated_event_draft.dart';
import 'package:sinapsis/features/timeline/domain/entities/historical_date_order.dart';

/// El hecho propuesto para la línea de tiempo y el orden de sus fechas (F40).
void main() {
  HistoricalDate year(int n, {bool bce = false, bool circa = false}) =>
      HistoricalDate(
        year: n,
        precision: DatePrecision.year,
        isBce: bce,
        isCirca: circa,
      );

  DatedEventDraft draft({
    HistoricalDate? date,
    HistoricalDate? endDate,
    String title = 'Estalla la guerra',
    int start = 10,
    int end = 15,
    String excerpt = 'en 191',
  }) => DatedEventDraft(
    date: date ?? year(1914),
    endDate: endDate,
    title: title,
    start: start,
    end: end,
    excerpt: excerpt.substring(0, end - start),
  );

  group('DatedEventDraft', () {
    test('guarda lo que se le da', () {
      final d = DatedEventDraft(
        date: year(1914),
        endDate: year(1918),
        title: 'Primera Guerra Mundial',
        start: 4,
        end: 9,
        excerpt: 'abcde',
      );
      expect(d.date, year(1914));
      expect(d.endDate, year(1918));
      expect(d.title, 'Primera Guerra Mundial');
      expect(d.start, 4);
      expect(d.end, 9);
      expect(d.excerpt, 'abcde');
    });

    test('el fin puede faltar', () {
      expect(draft().endDate, isNull);
    });

    test('el fin no puede ser anterior al inicio', () {
      expect(
        () => draft(date: year(1918), endDate: year(1914)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => draft(date: year(44), endDate: year(44, bce: true)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        draft(date: year(44, bce: true), endDate: year(44)).endDate,
        year(44),
      );
    });

    test('un fin del mismo día que el inicio es válido', () {
      expect(draft(date: year(1914), endDate: year(1914)).endDate, year(1914));
    });

    test('tiene título y una cita con texto', () {
      expect(() => draft(title: ''), throwsA(isA<AssertionError>()));
      expect(
        () => draft(start: 5, end: 5, excerpt: ''),
        throwsA(isA<AssertionError>()),
      );
      expect(() => draft(start: -1, end: 3), throwsA(isA<AssertionError>()));
      expect(
        () => DatedEventDraft(
          date: year(1914),
          title: 'X',
          start: 0,
          end: 3,
          excerpt: 'cuatro',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('igualdad por todos sus campos', () {
      expect(draft(), draft());
      expect(draft().hashCode, draft().hashCode);
      expect(draft(), isNot(draft(date: year(1915))));
      expect(draft(), isNot(draft(endDate: year(1918))));
      expect(draft(), isNot(draft(title: 'Otro')));
      expect(draft(), isNot(draft(start: 11, end: 16)));
      expect(draft(), isNot(draft(end: 14)));
      expect(draft(), isNot(draft(excerpt: 'in 191')));
    });

    test('se puede ver en un texto', () {
      expect(draft().toString(), contains('Estalla la guerra'));
      expect(draft().toString(), contains('[10, 15)'));
      expect(draft(endDate: year(1918)).toString(), contains('1918'));
    });
  });

  group('HistoricalDateOrder', () {
    test('compara por el primer día que cubre cada fecha', () {
      expect(year(1914).compareStart(year(1915)), lessThan(0));
      expect(year(1915).compareStart(year(1914)), greaterThan(0));
      expect(year(1914).compareStart(year(1914)), 0);
    });

    test('cruza el cero: 44 a.C. es antes que 44 d.C.', () {
      expect(year(44, bce: true).compareStart(year(44)), lessThan(0));
      expect(year(44).compareStart(year(44, bce: true)), greaterThan(0));
      expect(
        year(45, bce: true).compareStart(year(44, bce: true)),
        lessThan(0),
      );
    });

    test('un año y su primer día empiezan igual', () {
      const day = HistoricalDate(
        year: 1914,
        precision: DatePrecision.day,
        month: 1,
        day: 1,
      );
      expect(year(1914).compareStart(day), 0);
    });

    test('desempata por mes y por día', () {
      HistoricalDate on(int month, int day) => HistoricalDate(
        year: 1914,
        precision: DatePrecision.day,
        month: month,
        day: day,
      );
      expect(on(2, 5).compareStart(on(3, 1)), lessThan(0));
      expect(on(3, 1).compareStart(on(2, 5)), greaterThan(0));
      expect(on(3, 1).compareStart(on(3, 2)), lessThan(0));
      expect(on(3, 2).compareStart(on(3, 1)), greaterThan(0));
      expect(on(3, 1).compareStart(on(3, 1)), 0);
    });

    test('un siglo empieza antes que el año de su mitad', () {
      const century = HistoricalDate(
        year: 1801,
        precision: DatePrecision.century,
      );
      expect(century.compareStart(year(1850)), lessThan(0));
      expect(year(1850).compareStart(century), greaterThan(0));
    });

    test('sameReading ignora el «circa» y mira todo lo demás', () {
      expect(year(1500).sameReading(year(1500, circa: true)), isTrue);
      expect(year(1500, circa: true).sameReading(year(1500)), isTrue);
      expect(year(1500).sameReading(year(1501)), isFalse);
      expect(year(1500).sameReading(year(1500, bce: true)), isFalse);
      const month = HistoricalDate(
        year: 1500,
        precision: DatePrecision.month,
        month: 3,
      );
      expect(year(1500).sameReading(month), isFalse);
      expect(
        month.sameReading(
          const HistoricalDate(
            year: 1500,
            precision: DatePrecision.month,
            month: 4,
          ),
        ),
        isFalse,
      );
      const day = HistoricalDate(
        year: 1500,
        precision: DatePrecision.day,
        month: 3,
        day: 1,
      );
      expect(
        day.sameReading(
          const HistoricalDate(
            year: 1500,
            precision: DatePrecision.day,
            month: 3,
            day: 2,
          ),
        ),
        isFalse,
      );
      expect(
        year(1500).sameReading(
          const HistoricalDate(year: 1500, precision: DatePrecision.century),
        ),
        isFalse,
      );
    });
  });
}
