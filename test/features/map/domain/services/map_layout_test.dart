import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/services/map_layout.dart';

/// El layout de fuerzas del mapa (F14): con uniones que pesan, con grupos, en
/// caliente y sin azar.
void main() {
  double distance(MapLayout layout, int a, int b) {
    final dx = layout.xs[a] - layout.xs[b];
    final dy = layout.ys[a] - layout.ys[b];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// La distancia media entre los pares de [pairs].
  double meanDistance(MapLayout layout, Iterable<(int, int)> pairs) {
    var total = 0.0;
    var n = 0;
    for (final (a, b) in pairs) {
      total += distance(layout, a, b);
      n++;
    }
    return total / n;
  }

  Iterable<(int, int)> pairsWithin(List<int> nodes) => [
    for (var i = 0; i < nodes.length; i++)
      for (var j = i + 1; j < nodes.length; j++) (nodes[i], nodes[j]),
  ];

  test('sin nodos no hay nada, y con uno va al centro', () {
    expect(layoutForces(count: 0, links: const []).count, 0);

    final single = layoutForces(count: 1, links: const [], extent: 600);
    expect(single.xs.single, 300);
    expect(single.ys.single, 300);
  });

  test('sin azar: el mismo grafo da exactamente el mismo layout', () {
    final links = [
      const MapLayoutLink(0, 1, 3),
      const MapLayoutLink(1, 2, 1),
      const MapLayoutLink(2, 3, 2),
      const MapLayoutLink(3, 0, 5),
    ];

    final a = layoutForces(count: 5, links: links);
    final b = layoutForces(count: 5, links: links);

    expect(b.xs, a.xs);
    expect(b.ys, a.ys);
  });

  test('los nodos unidos quedan más cerca que los que no', () {
    // Dos triángulos sin nada entre ellos.
    final links = [
      for (final (a, b) in [(0, 1), (1, 2), (0, 2), (3, 4), (4, 5), (3, 5)])
        MapLayoutLink(a, b, 4),
    ];

    final layout = layoutForces(count: 6, links: links);

    final within = meanDistance(layout, [
      ...pairsWithin([0, 1, 2]),
      ...pairsWithin([3, 4, 5]),
    ]);
    final across = meanDistance(layout, [
      for (final a in [0, 1, 2])
        for (final b in [3, 4, 5]) (a, b),
    ]);
    expect(within, lessThan(across));
  });

  test('lo que más pesa queda más cerca', () {
    final layout = layoutForces(
      count: 3,
      links: [const MapLayoutLink(0, 1, 100), const MapLayoutLink(0, 2, 1)],
    );

    expect(distance(layout, 0, 1), lessThan(distance(layout, 0, 2)));
  });

  test('sin uniones con peso, los nodos igual se reparten, sin caerse en el '
      'mismo punto', () {
    final layout = layoutForces(
      count: 4,
      links: const [MapLayoutLink(0, 1, 0)],
    );

    for (final (a, b) in pairsWithin([0, 1, 2, 3])) {
      expect(distance(layout, a, b), greaterThan(1));
    }
    expect(layout.xs.every((x) => x.isFinite), isTrue);
  });

  group('los grupos', () {
    /// Tres grupos de 12 nodos, con muchas uniones dentro y unas pocas entre
    /// ellos.
    ({List<MapLayoutLink> links, Int32List groups}) planted() {
      final random = math.Random(11);
      final links = <MapLayoutLink>[];
      final groups = Int32List(36);
      for (var i = 0; i < 36; i++) {
        groups[i] = (i ~/ 12) * 7 + 3;
      }
      for (var i = 0; i < 36; i++) {
        for (var j = i + 1; j < 36; j++) {
          final same = i ~/ 12 == j ~/ 12;
          if (random.nextDouble() < (same ? 0.3 : 0.05)) {
            links.add(MapLayoutLink(i, j, same ? 3 : 1));
          }
        }
      }
      return (links: links, groups: groups);
    }

    double separation(MapLayout layout) {
      final within = <(int, int)>[
        for (var g = 0; g < 3; g++)
          ...pairsWithin([for (var i = 0; i < 12; i++) g * 12 + i]),
      ];
      final across = <(int, int)>[
        for (var i = 0; i < 36; i++)
          for (var j = i + 1; j < 36; j++)
            if (i ~/ 12 != j ~/ 12) (i, j),
      ];
      return meanDistance(layout, within) / meanDistance(layout, across);
    }

    test('con la cohesión del grupo, cada grupo queda más compacto', () {
      final data = planted();

      final free = layoutForces(count: 36, links: data.links);
      final grouped = layoutForces(
        count: 36,
        links: data.links,
        groups: data.groups,
      );

      expect(separation(grouped), lessThan(separation(free)));
      expect(separation(grouped), lessThan(0.6));
    });

    test('las identidades de grupo pueden ser cualquier número', () {
      final data = planted();

      final layout = layoutForces(
        count: 36,
        links: data.links,
        groups: Int32List.fromList([
          for (var i = 0; i < 36; i++) 1000000 + i ~/ 12,
        ]),
      );

      expect(layout.xs.every((x) => x.isFinite), isTrue);
    });
  });

  group('en caliente', () {
    /// Un anillo de 30 nodos unidos con el siguiente.
    List<MapLayoutLink> ring() => [
      for (var i = 0; i < 30; i++) MapLayoutLink(i, (i + 1) % 30, 2),
    ];

    test('partir de un layout ya calculado apenas lo mueve', () {
      final cold = layoutForces(count: 30, links: ring());

      final warm = layoutForces(
        count: 30,
        links: ring(),
        startX: cold.xs,
        startY: cold.ys,
        iterations: 60,
      );

      final k = math.sqrt(900 * 900 / 30);
      var moved = 0.0;
      for (var i = 0; i < 30; i++) {
        moved += math.sqrt(
          math.pow(warm.xs[i] - cold.xs[i], 2) +
              math.pow(warm.ys[i] - cold.ys[i], 2),
        );
      }
      expect(moved / 30, lessThan(k * 0.2));
    });

    test('un nodo nuevo nace junto a su vecino, y no encima', () {
      final cold = layoutForces(count: 30, links: ring());
      final x = Float64List.fromList([...cold.xs, double.nan]);
      final y = Float64List.fromList([...cold.ys, double.nan]);

      final placed = layoutForces(
        count: 31,
        links: [...ring(), const MapLayoutLink(30, 4, 2)],
        startX: x,
        startY: y,
        iterations: 0,
      );

      final gap = distance(placed, 30, 4);
      expect(gap, greaterThan(0));
      expect(gap, lessThan(900 / 31));
      // Los que ya estaban no se movieron.
      for (var i = 0; i < 30; i++) {
        expect(placed.xs[i], cold.xs[i]);
        expect(placed.ys[i], cold.ys[i]);
      }
    });

    test('sin ninguna posición previa es lo mismo que empezar de cero', () {
      final links = ring();
      final scratch = layoutForces(count: 30, links: links);

      final nan = Float64List(30)..fillRange(0, 30, double.nan);
      final empty = layoutForces(
        count: 30,
        links: links,
        startX: nan,
        startY: nan,
      );

      expect(empty.xs, scratch.xs);
    });
  });

  test('300 nodos y sus uniones se calculan en un tiempo razonable', () {
    final random = math.Random(2);
    final links = [
      for (var i = 0; i < 1500; i++)
        MapLayoutLink(
          random.nextInt(300),
          random.nextInt(300),
          1.0 + random.nextInt(5),
        ),
    ].where((l) => l.a != l.b).toList();

    final watch = Stopwatch()..start();
    final layout = layoutForces(count: 300, links: links, iterations: 200);
    watch.stop();

    expect(layout.count, 300);
    expect(layout.xs.every((x) => x.isFinite), isTrue);
    // Cotas muy holgadas: la medición de verdad se hace en el emulador.
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });
}
