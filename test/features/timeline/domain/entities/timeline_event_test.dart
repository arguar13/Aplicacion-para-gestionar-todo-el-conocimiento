import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_axis.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

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

  group('un hecho fechado dentro de un documento (F40)', () {
    TimelineEvent fact({
      HistoricalDate? end,
      HistoricalDate? date,
      String? renditionId,
      int? startOffset,
      ContentOrigin? origin = ContentOrigin.user,
    }) => TimelineEvent(
      itemId: 'libro',
      title: 'La Gran Guerra',
      itemTitle: 'Historia del siglo XX',
      date: date ?? dateOf(1914),
      end: end,
      sourceKind: SourceKind.document,
      datedEventId: 'h1',
      renditionId: renditionId,
      startOffset: startOffset,
      origin: origin,
    );

    test('sin fin es un momento como cualquier fecha', () {
      final event = fact();

      expect(event.isRange, isFalse);
      expect(event.from, 1914.0);
      expect(event.to, 1915.0);
    });

    test('con fin va de donde empieza el inicio a donde termina el fin', () {
      final event = fact(end: dateOf(1918));

      expect(event.isRange, isTrue);
      expect(event.from, 1914.0);
      expect(event.to, 1919.0);
    });

    test('el fin puede ser de otra precisión', () {
      final event = fact(
        end: const HistoricalDate(
          year: 1918,
          precision: DatePrecision.month,
          month: 11,
        ),
      );

      expect(event.to, axisStartOfMonth(1918, 12));
    });

    test('un tramo cruza el cero', () {
      final event = fact(date: dateOf(10, bce: true), end: dateOf(10));

      expect(event.from, -9.0);
      expect(event.to, 11.0);
    });

    test('con fin ya no es un período: se sabe de cuándo a cuándo', () {
      final century = dateOf(1900, precision: DatePrecision.century);

      expect(fact(date: century).isPeriod, isTrue);
      expect(fact(date: century, end: dateOf(1950)).isPeriod, isFalse);
    });

    test('el circa difumina por la precisión del inicio, no por el largo del '
        'tramo', () {
      final event = fact(date: dateOf(1500, circa: true), end: dateOf(1600));

      expect(event.fuzz, 0.5);
      expect(event.reachFrom, 1499.5);
      expect(event.reachTo, 1601.5);
    });

    test('dos hechos del mismo documento en la misma fecha tienen un orden '
        'total: el de su identificador', () {
      TimelineEvent withId(String id) => TimelineEvent(
        itemId: 'libro',
        title: id,
        date: dateOf(1900),
        sourceKind: SourceKind.document,
        datedEventId: id,
      );
      final a = withId('a');
      final z = withId('z');

      expect(compareTimelineEvents(a, z), isNegative);
      expect(compareTimelineEvents(z, a), isPositive);
      expect(compareTimelineEvents(a, withId('a')), isZero);
    });

    test('se distingue de la «Fecha del hecho» del elemento', () {
      final own = eventAt('roma', dateOf(476));

      expect(own.isDatedEvent, isFalse);
      expect(own.documentTitle, own.title);
      expect(own.isAi, isFalse);
      expect(own.hasAnchor, isFalse);

      final event = fact();
      expect(event.isDatedEvent, isTrue);
      expect(event.title, 'La Gran Guerra');
      expect(event.documentTitle, 'Historia del siglo XX');
    });

    test('lo de la IA y la cita se leen de los campos', () {
      expect(fact(origin: ContentOrigin.ai).isAi, isTrue);
      expect(fact().isAi, isFalse);
      expect(fact(renditionId: 'texto', startOffset: 4).hasAnchor, isTrue);
      expect(fact(renditionId: 'texto').hasAnchor, isFalse);
      expect(fact(startOffset: 4).hasAnchor, isFalse);
    });
  });
}
