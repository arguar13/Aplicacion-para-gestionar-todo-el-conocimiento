import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/services/lane_layout.dart';
import 'package:sinapsis/features/timeline/domain/services/timeline_index.dart';

import '../../timeline_fixtures.dart';

/// El criterio de F9 para la línea de tiempo: con diez mil eventos, lo que
/// cuesta mostrar una ventana es proporcional a lo que hay en la ventana, no a
/// lo que hay guardado.
///
/// Dos garantías distintas. La que decide es el conteo de nodos que el índice
/// miró —determinista, no depende de la máquina—. El cronómetro es una red de
/// seguridad con un margen enorme: atrapa una regresión a recorrer todo, no
/// mide el rendimiento fino.
void main() {
  const total = 10000;

  late List<TimelineEvent> events;
  late TimelineIndex index;

  /// Diez mil hechos repartidos entre 3000 a.C. y 2025 d.C., con de todo: años,
  /// meses, días, décadas, siglos y aproximados.
  List<TimelineEvent> tenThousand() {
    final random = Random(2026);
    return [
      for (var i = 0; i < total; i++)
        () {
          final bce = random.nextInt(3) == 0;
          return eventAt(
            'e${i.toString().padLeft(5, '0')}',
            HistoricalDate(
              year: 1 + random.nextInt(bce ? 3000 : 2025),
              precision: switch (random.nextInt(10)) {
                0 => DatePrecision.century,
                1 || 2 => DatePrecision.decade,
                3 || 4 => DatePrecision.day,
                5 => DatePrecision.month,
                _ => DatePrecision.year,
              },
              month: 1 + random.nextInt(12),
              day: 1 + random.nextInt(28),
              isBce: bce,
              isCirca: random.nextInt(8) == 0,
            ),
          );
        }(),
    ];
  }

  setUpAll(() {
    events = tenThousand();
    index = TimelineIndex(events);
  });

  test('el índice conoce los diez mil eventos', () {
    expect(index.length, total);
  });

  test('una ventana que lo abarca todo devuelve todo', () {
    final all = index.window(-5000, 3000);

    expect(all.events, hasLength(total));
  });

  test('una ventana chica cuesta lo que se ve, no lo que hay', () {
    final small = index.window(1500, 1520);

    // Alrededor de 20 años de un total de ~4.500 años con 10.000 eventos, más
    // los tramos largos que la atraviesan.
    expect(small.events.length, lessThan(400));
    expect(small.events, isNotEmpty);

    // Cada evento que se ve cuesta unos pocos nodos, más el descenso por el
    // árbol; nada parecido a recorrer diez mil.
    expect(small.examined, lessThan(small.events.length * 6 + 100));
    expect(small.examined, lessThan(total ~/ 10));
  });

  test('el costo crece con la ventana, no con el total', () {
    final widths = [5.0, 20.0, 100.0, 500.0, 2000.0];
    final costs = [
      for (final width in widths) index.window(1000, 1000 + width).examined,
    ];

    for (var i = 1; i < costs.length; i++) {
      expect(costs[i], greaterThanOrEqualTo(costs[i - 1]));
    }
    // La ventana más chica cuesta una fracción de la que lo abarca casi todo.
    expect(costs.first * 20, lessThan(index.window(-5000, 3000).examined));
  });

  test('dibujar una ventana reparte solo lo visible en carriles', () {
    final window = index.window(1500, 1520);

    final layout = layoutLanes(window.events, maxLanes: 12);

    expect(layout.placed.length + layout.hidden, window.events.length);
    expect(layout.laneCount, lessThanOrEqualTo(12));
  });

  test('recorrer todo el eje ventana a ventana termina rápido', () {
    // Mil cuadros de un gesto de arrastre: consulta más reparto en carriles.
    final stopwatch = Stopwatch()..start();
    var drawn = 0;
    for (var frame = 0; frame < 1000; frame++) {
      final from = -3000 + frame * 5.0;
      final window = index.window(from, from + 40);
      drawn += layoutLanes(window.events, maxLanes: 12).placed.length;
    }
    stopwatch.stop();

    expect(drawn, greaterThan(0));
    // Sobra: en una máquina normal son decenas de milisegundos. El margen es
    // para que una máquina cargada no dé un falso rojo; una regresión a
    // recorrer los diez mil eventos por cuadro tardaría minutos.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('armar el índice de diez mil eventos es rápido', () {
    final stopwatch = Stopwatch()..start();
    final built = TimelineIndex(events);
    stopwatch.stop();

    expect(built.length, total);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
