import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_density.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

import '../../timeline_fixtures.dart';

/// La densidad del mini mapa (F40): cuántos hechos hay en cada tramo de todo
/// el rango de los datos.
void main() {
  /// La densidad de [events] sobre el rango que ellos mismos ocupan, como la
  /// arma el lienzo, con [bins] barras.
  TimelineDensity of(List<TimelineEvent> events, {int bins = 10}) {
    final extent = TimelineIndex(events).extent!;
    return TimelineDensity.of(
      events,
      from: extent.from,
      to: extent.to,
      bins: bins,
    );
  }

  group('las barras', () {
    test('donde se juntan los hechos, la barra es más alta', () {
      // Tres hechos en el primer décimo, uno en el último, nada en el medio.
      final density = of([
        eventAt('a', dateOf(1000)),
        eventAt('b', dateOf(1001)),
        eventAt('c', dateOf(1002)),
        eventAt('z', dateOf(1100)),
      ]);

      expect(density.length, 10);
      expect(density.levels.first, 1);
      expect(density.levels.last, greaterThan(0));
      expect(density.levels.last, lessThan(density.levels.first));
      expect(density.levels.sublist(1, 9), everyElement(0));
    });

    test('la altura achata los picos con la raíz: un tramo con cuatro veces '
        'los hechos de otro no se ve cuatro veces más alto', () {
      final density = of([
        for (var i = 0; i < 4; i++) eventAt('a$i', dateOf(1000)),
        eventAt('b', dateOf(1100)),
      ]);

      expect(density.levels.first, 1);
      expect(density.levels.last, closeTo(0.5, 1e-9)); // sqrt(1 / 4)
    });

    test('un hecho largo cuenta en las barras que cubre, no solo donde '
        'empieza', () {
      // Un siglo entero entre dos años sueltos que fijan el rango 1000–2000,
      // en ocho barras de unos 125 años: 1301–1400 cae en la tercera y la
      // cuarta, y en ninguna otra.
      final density = of([
        eventAt('inicio', dateOf(1000)),
        eventAt('siglo', dateOf(1301, precision: DatePrecision.century)),
        eventAt('fin', dateOf(1999)),
      ], bins: 8);

      expect(density.levels[1], 0);
      expect(density.levels[2], greaterThan(0));
      expect(density.levels[3], greaterThan(0));
      expect(density.levels[4], 0);
    });

    test('un hecho que termina justo en el borde de una barra no cuenta en la '
        'siguiente', () {
      // Un año que va de 1000 a 1001, y un rango de 1000 a 1010 en diez
      // barras: cada barra mide exactamente un año.
      final density = TimelineDensity.of(
        [eventAt('a', dateOf(1000))],
        from: 1000,
        to: 1010,
        bins: 10,
      );

      expect(density.levels.first, 1);
      expect(density.levels.sublist(1), everyElement(0));
    });

    test('sin hechos todas las barras están vacías', () {
      final density = TimelineDensity.of(const [], from: 0, to: 100, bins: 5);

      expect(density.levels, everyElement(0));
    });

    test('un rango sin ancho —un solo año exacto en un solo punto— no rompe '
        'la cuenta', () {
      final density = TimelineDensity.of(
        [eventAt('a', dateOf(1000))],
        from: 1000,
        to: 1000,
        bins: 4,
      );

      expect(density.levels.reduce((a, b) => a > b ? a : b), 1);
    });
  });

  group('de año a posición', () {
    test('fractionOf y yearAt son inversas, también fuera del rango', () {
      final density = TimelineDensity.of(const [], from: 100, to: 300);

      expect(density.fractionOf(100), 0);
      expect(density.fractionOf(300), 1);
      expect(density.fractionOf(200), 0.5);
      expect(density.fractionOf(0), -0.5);
      expect(density.yearAt(0.25), 150);
      expect(density.yearAt(density.fractionOf(777)), closeTo(777, 1e-9));
    });
  });

  group('escala', () {
    test('diez mil hechos se cuentan de una vez y bien', () {
      final events = tenThousandTimelineEvents();

      final extent = TimelineIndex(events).extent!;
      final watch = Stopwatch()..start();
      final density = TimelineDensity.of(
        events,
        from: extent.from,
        to: extent.to,
      );
      watch.stop();

      expect(density.length, TimelineDensity.binCount);
      expect(density.levels.reduce((a, b) => a > b ? a : b), 1);
      expect(density.levels.every((l) => l >= 0 && l <= 1), isTrue);
      // Un recorrido y un acumulado: no un cruce de cada hecho con cada barra.
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });
}
