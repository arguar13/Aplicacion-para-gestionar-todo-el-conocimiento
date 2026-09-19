import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';

import '../../timeline_fixtures.dart';

void main() {
  Map<String, int> lanes(LaneLayout layout) => {
    for (final p in layout.placed) p.event.itemId: p.lane,
  };

  group('reparto en carriles', () {
    test('sin eventos, no hay carriles', () {
      final layout = layoutLanes(const [], maxLanes: 5);

      expect(layout.placed, isEmpty);
      expect(layout.hidden, 0);
      expect(layout.laneCount, 0);
    });

    test('lo que no se solapa comparte carril', () {
      final layout = layoutLanes([
        eventAt('a', dateOf(100)),
        eventAt('b', dateOf(200)),
        eventAt('c', dateOf(300)),
      ], maxLanes: 5);

      expect(lanes(layout), {'a': 0, 'b': 0, 'c': 0});
      expect(layout.laneCount, 1);
    });

    test('lo que se solapa va a otro carril', () {
      final layout = layoutLanes([
        eventAt('a', dateOf(100, precision: DatePrecision.decade)), // 100–110
        eventAt('b', dateOf(105)), // 105–106
      ], maxLanes: 5);

      expect(lanes(layout), {'a': 0, 'b': 1});
      expect(layout.laneCount, 2);
    });

    test('un carril que ya quedó libre se reusa', () {
      final layout = layoutLanes([
        eventAt('largo', dateOf(100, precision: DatePrecision.decade)),
        eventAt('corto', dateOf(102)),
        eventAt('despues', dateOf(150)),
      ], maxLanes: 5);

      // "despues" empieza cuando ambos terminaron: vuelve al primero.
      expect(lanes(layout), {'largo': 0, 'corto': 1, 'despues': 0});
    });

    test('dos años seguidos, uno pegado al otro, no se pisan', () {
      final layout = layoutLanes([
        eventAt('a', dateOf(476)),
        eventAt('b', dateOf(477)),
      ], maxLanes: 5);

      expect(lanes(layout), {'a': 0, 'b': 0});
    });

    test('usa el menor número de carriles posible', () {
      // Tres tramos mutuamente solapados necesitan tres; el cuarto entra
      // después de que el primero termina.
      final layout = layoutLanes([
        eventAt('a', dateOf(100, precision: DatePrecision.decade)), // 100–110
        eventAt('b', dateOf(102, precision: DatePrecision.decade)), // 102–112
        eventAt('c', dateOf(104, precision: DatePrecision.decade)), // 104–114
        eventAt('d', dateOf(111)), // 111–112
      ], maxLanes: 10);

      expect(layout.laneCount, 3);
      expect(lanes(layout)['d'], 0);
    });
  });

  group('límite de carriles', () {
    test('lo que no entra se cuenta y no se dibuja', () {
      final layout = layoutLanes([
        eventAt('a', dateOf(100, precision: DatePrecision.decade)),
        eventAt('b', dateOf(101, precision: DatePrecision.decade)),
        eventAt('c', dateOf(102, precision: DatePrecision.decade)),
        eventAt('d', dateOf(103, precision: DatePrecision.decade)),
      ], maxLanes: 2);

      expect(layout.placed, hasLength(2));
      expect(layout.hidden, 2);
      expect(layout.laneCount, 2);
      expect(layout.placed.every((p) => p.lane < 2), isTrue);
    });

    test('placed más hidden es siempre el total', () {
      final random = Random(3);
      final events = [
        for (var i = 0; i < 300; i++)
          eventAt(
            'e$i',
            dateOf(1 + random.nextInt(60), precision: DatePrecision.decade),
          ),
      ];

      for (final max in [1, 3, 8, 40]) {
        final layout = layoutLanes(events, maxLanes: max);

        expect(layout.placed.length + layout.hidden, events.length);
        expect(layout.laneCount, lessThanOrEqualTo(max));
      }
    });
  });

  group('espacio mínimo', () {
    test('sin espacio mínimo, dos rótulos vecinos no se distinguen', () {
      final layout = layoutLanes([
        eventAt('a', dateOf(476)),
        eventAt('b', dateOf(478)),
      ], maxLanes: 5);

      expect(lanes(layout), {'a': 0, 'b': 0});
    });

    test('con espacio mínimo, un evento puntual ocupa lo que su rótulo', () {
      final layout = layoutLanes(
        [eventAt('a', dateOf(476)), eventAt('b', dateOf(478))],
        maxLanes: 5,
        // El rótulo necesita cinco años de eje a este zoom.
        footprint: (_) => 5,
      );

      expect(lanes(layout), {'a': 0, 'b': 1});
    });

    test('el espacio mínimo no achica a un tramo que ya es más ancho', () {
      final layout = layoutLanes(
        [
          eventAt('siglo', dateOf(100, precision: DatePrecision.century)),
          eventAt('b', dateOf(190)),
        ],
        maxLanes: 5,
        footprint: (_) => 1,
      );

      // El siglo llega hasta 200: "b" (190) queda en otro carril.
      expect(lanes(layout), {'siglo': 0, 'b': 1});
    });

    test('el espacio mínimo puede depender del evento', () {
      final layout = layoutLanes(
        [
          eventAt('corto', dateOf(100), title: 'A'),
          eventAt('largo', dateOf(102), title: 'Un título muy largo'),
          eventAt('siguiente', dateOf(104), title: 'B'),
        ],
        maxLanes: 5,
        footprint: (e) => e.title.length.toDouble() / 4,
      );

      // "largo" ocupa ~4.75 años y se lleva por delante a "siguiente".
      expect(lanes(layout)['largo'], isNot(lanes(layout)['siguiente']));
    });
  });

  group('estabilidad', () {
    test(
      'el mismo conjunto se reparte igual sea cual sea el orden de entrada',
      () {
        final random = Random(9);
        final events = [
          for (var i = 0; i < 100; i++)
            eventAt(
              'e${i.toString().padLeft(3, '0')}',
              dateOf(1 + random.nextInt(200), precision: DatePrecision.decade),
            ),
        ];
        final shuffled = [...events]..shuffle(Random(1));

        expect(
          lanes(layoutLanes(shuffled, maxLanes: 50)),
          lanes(layoutLanes(events, maxLanes: 50)),
        );
      },
    );
  });
}
