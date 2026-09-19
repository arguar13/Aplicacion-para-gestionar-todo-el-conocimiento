import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

import '../../timeline_fixtures.dart';

void main() {
  List<String> ids(TimelineWindow window) =>
      window.events.map((e) => e.itemId).toList();

  group('ventana', () {
    test('un índice vacío no devuelve nada y no tiene extensión', () {
      final index = TimelineIndex(const []);

      expect(index.isEmpty, isTrue);
      expect(index.length, 0);
      expect(index.extent, isNull);
      expect(index.window(-1000, 3000).events, isEmpty);
    });

    test('devuelve en orden cronológico, sin importar el de entrada', () {
      final index = TimelineIndex([
        eventAt('caida', dateOf(476)),
        eventAt('cesar', dateOf(44, bce: true)),
        eventAt('constantinopla', dateOf(1453)),
        eventAt('era', dateOf(1)),
        eventAt('cristo', dateOf(1, bce: true)),
      ]);

      expect(ids(index.window(-100, 2000)), [
        'cesar',
        'cristo',
        'era',
        'caida',
        'constantinopla',
      ]);
    });

    test('a.C. y d.C. quedan pegados en el eje, sin un hueco en el cero', () {
      final index = TimelineIndex([
        eventAt('a', dateOf(1, bce: true)),
        eventAt('b', dateOf(1)),
      ]);

      // Una ventana de un año justo antes y justo después de la era ve un
      // evento cada una.
      expect(ids(index.window(0, 1)), ['a']);
      expect(ids(index.window(1, 2)), ['b']);
      expect(ids(index.window(0.5, 1.5)), ['a', 'b']);
    });

    test('la ventana es semiabierta: lo que termina justo donde empieza, o '
        'empieza justo donde termina, no entra', () {
      final index = TimelineIndex([eventAt('a', dateOf(476))]); // [476, 477)

      expect(ids(index.window(477, 480)), isEmpty);
      expect(ids(index.window(470, 476)), isEmpty);
      expect(ids(index.window(476.5, 476.6)), ['a']);
      expect(ids(index.window(470, 476.001)), ['a']);
    });

    test('un tramo que empieza antes de la ventana y sigue dentro, entra', () {
      final index = TimelineIndex([
        eventAt('siglo', dateOf(1, precision: DatePrecision.century)),
      ]);

      expect(ids(index.window(50, 60)), ['siglo']);
    });

    test('el borde difuso de un circa cuenta aunque su centro esté fuera', () {
      // "circa siglo II" ocupa [200, 300) y corre cincuenta años por lado.
      final circa = eventAt(
        'circa',
        dateOf(200, circa: true, precision: DatePrecision.century),
      );
      final index = TimelineIndex([circa]);

      expect(ids(index.window(340, 345)), ['circa']);
      expect(ids(index.window(100, 149)), isEmpty);
    });

    test('dos fechas del mismo elemento son dos eventos en el eje', () {
      final index = TimelineIndex([
        eventAt('roma', dateOf(753, bce: true)),
        eventAt('roma', dateOf(476)),
      ]);

      expect(ids(index.window(-1000, 1000)), ['roma', 'roma']);
    });

    test('los que empatan en tramo salen siempre en el mismo orden', () {
      final events = [
        eventAt('c', dateOf(500)),
        eventAt('a', dateOf(500)),
        eventAt('b', dateOf(500)),
      ];

      expect(ids(TimelineIndex(events).window(0, 1000)), ['a', 'b', 'c']);
      expect(ids(TimelineIndex(events.reversed).window(0, 1000)), [
        'a',
        'b',
        'c',
      ]);
    });

    test('a igual inicio, primero el tramo más largo', () {
      final index = TimelineIndex([
        eventAt('anio', dateOf(1900)),
        eventAt('decada', dateOf(1900, precision: DatePrecision.decade)),
        eventAt('siglo', dateOf(1900, precision: DatePrecision.century)),
      ]);

      expect(ids(index.window(1800, 2100)), ['siglo', 'decada', 'anio']);
    });
  });

  group('extensión', () {
    test('va del primer alcance al último, con los bordes difusos', () {
      final index = TimelineIndex([
        eventAt('a', dateOf(44, bce: true)),
        eventAt('b', dateOf(1453)),
        eventAt('c', dateOf(1000, circa: true)), // alcanza 999.5 – 1001.5
      ]);

      expect(index.extent, (from: -43.0, to: 1454.0));
    });

    test('un circa en el extremo ensancha la extensión', () {
      final index = TimelineIndex([
        eventAt('a', dateOf(1453, circa: true)), // 1452.5 – 1454.5
      ]);

      expect(index.extent, (from: 1452.5, to: 1454.5));
    });
  });

  group('costo', () {
    test('un tramo larguísimo al principio no obliga a recorrer lo que hay '
        'entre medio', () {
      // Un siglo entero y cinco mil eventos de un año adentro suyo. Con un
      // simple máximo acumulado del final, el siglo haría que toda consulta
      // dentro de él recorriera los cinco mil.
      final events = [
        eventAt('siglo', dateOf(1, precision: DatePrecision.century)),
        for (var i = 0; i < 5000; i++)
          eventAt('e${i.toString().padLeft(4, '0')}', dateOf(1 + i % 99)),
      ];
      final index = TimelineIndex(events);

      final window = index.window(95, 96);

      // El siglo y los cincuenta y pico eventos del año 95.
      expect(window.events.map((e) => e.itemId), contains('siglo'));
      expect(window.events.length, lessThan(100));
      expect(window.examined, lessThan(600));
      expect(window.examined, lessThan(events.length ~/ 5));
    });
  });

  group('contra la búsqueda exhaustiva', () {
    test(
      'devuelve exactamente lo mismo que filtrar todo, en el mismo orden',
      () {
        final random = Random(42);
        final events = [
          for (var i = 0; i < 400; i++) _randomEvent(random, 'e$i'),
        ];
        final index = TimelineIndex(events);
        final sorted = [...events]..sort(compareTimelineEvents);

        for (var q = 0; q < 300; q++) {
          final from = -3000 + random.nextDouble() * 5200;
          final to = from + 0.01 + random.nextDouble() * 400;

          final expected = sorted
              .where((e) => e.reachFrom < to && e.reachTo > from)
              .toList();

          expect(
            index.window(from, to).events,
            expected,
            reason: 'ventana [$from, $to)',
          );
        }
      },
    );
  });
}

TimelineEvent _randomEvent(Random random, String id) {
  final bce = random.nextBool();
  final precision = DatePrecision.values[random.nextInt(5)];
  return eventAt(
    id,
    HistoricalDate(
      year: 1 + random.nextInt(bce ? 3000 : 2100),
      precision: precision,
      month: 1 + random.nextInt(12),
      day: 1 + random.nextInt(28),
      isBce: bce,
      isCirca: random.nextInt(4) == 0,
    ),
  );
}
