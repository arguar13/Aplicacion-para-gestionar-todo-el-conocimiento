import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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

  /// Lo que más se movió algún nodo entre dos layouts.
  double maxMove(MapLayout before, MapLayout after) {
    var most = 0.0;
    for (var i = 0; i < before.count; i++) {
      most = math.max(
        most,
        math.sqrt(
          math.pow(after.xs[i] - before.xs[i], 2) +
              math.pow(after.ys[i] - before.ys[i], 2),
        ),
      );
    }
    return most;
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

  group('sin ninguna unión', () {
    test('van en una espiral compacta, no desparramados', () {
      final layout = layoutForces(count: 300, links: const []);

      // Compacta: con 300 nodos, dentro de un radio de unos 1.600 píxeles, y no
      // de las decenas de miles que da la repulsión sola.
      var farthest = 0.0;
      for (var i = 0; i < 300; i++) {
        farthest = math.max(
          farthest,
          math.sqrt(
            math.pow(layout.xs[i] - 450, 2) + math.pow(layout.ys[i] - 450, 2),
          ),
        );
      }
      expect(farthest, lessThan(1800));
      // Y con lugar para cada uno: ningún par más cerca que una etiqueta.
      var closest = double.infinity;
      for (var i = 0; i < 300; i++) {
        for (var j = i + 1; j < 300; j++) {
          closest = math.min(closest, distance(layout, i, j));
        }
      }
      expect(closest, greaterThan(40));
    });

    test('son deterministas y respetan el orden por grupo', () {
      final groups = Int32List.fromList([1, 0, 1, 0, 2]);

      final a = layoutForces(count: 5, links: const [], groups: groups);
      final b = layoutForces(count: 5, links: const [], groups: groups);

      expect(b.xs, a.xs);
      // Los del grupo 0 (nodos 1 y 3) quedan en los dos primeros lugares de la
      // espiral, los más cercanos al centro.
      final fromCenter = [
        for (var i = 0; i < 5; i++)
          math.sqrt(math.pow(a.xs[i] - 450, 2) + math.pow(a.ys[i] - 450, 2)),
      ];
      expect(fromCenter[1], lessThan(fromCenter[0]));
      expect(fromCenter[3], lessThan(fromCenter[4]));
    });
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
      expect(maxMove(cold, warm), lessThan(k * 0.1));
    });

    test('un layout con comunidades, ya calculado, tampoco salta: es un '
        'layout congelado por el enfriamiento y no un equilibrio', () {
      // Dos grupos de cuatro muy unidos, con uniones débiles entre ellos: de
      // este caso salió el defecto de dejar moverse a lo ya acomodado.
      final links = <MapLayoutLink>[
        for (final base in [0, 4])
          for (var i = 0; i < 4; i++)
            for (var j = i + 1; j < 4; j++)
              MapLayoutLink(base + i, base + j, 4),
        const MapLayoutLink(0, 4, 2),
        const MapLayoutLink(1, 5, 2),
      ];
      final groups = Int32List.fromList([0, 0, 0, 0, 1, 1, 1, 1]);
      final cold = layoutForces(count: 8, links: links, groups: groups);

      for (final iterations in [10, 30, 60]) {
        final warm = layoutForces(
          count: 8,
          links: links,
          groups: groups,
          startX: cold.xs,
          startY: cold.ys,
          iterations: iterations,
        );
        final k = math.sqrt(900 * 900 / 8);
        expect(
          maxMove(cold, warm),
          lessThan(k * 0.1),
          reason: '$iterations iteraciones',
        );
      }
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

  // Lo que ve la persona en el teléfono: el mapa de vínculos con un
  // componente grande y unos pocos pares sueltos acababa con 53 pares de cajas
  // encimadas en un rincón y los pares a miles de píxeles.
  group('legible (layoutReadable)', () {
    /// Un componente de 23 —un núcleo con cadenas, como suelen quedar los
    /// vínculos— y dos pares sueltos.
    List<MapLayoutLink> phoneLike() => [
      for (var i = 1; i < 23; i++) MapLayoutLink(i % 5 == 0 ? 0 : i - 1, i, 2),
      const MapLayoutLink(3, 17, 2),
      const MapLayoutLink(8, 21, 3),
      const MapLayoutLink(23, 24, 2),
      const MapLayoutLink(25, 26, 2),
    ];

    /// Las cajas de cada nodo, centradas en su posición.
    List<Rect> boxes(
      MapLayout layout,
      Float64List widths,
      Float64List heights,
    ) => [
      for (var i = 0; i < layout.count; i++)
        Rect.fromCenter(
          center: layout.positionOf(i),
          width: widths[i],
          height: heights[i],
        ),
    ];

    /// Cuántos pares de cajas se pisan.
    int overlaps(List<Rect> boxes) {
      var count = 0;
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          // `overlaps` cuenta el borde compartido: se pide aire de verdad.
          final inter = boxes[i].intersect(boxes[j]);
          if (inter.width > 0 && inter.height > 0) count++;
        }
      }
      return count;
    }

    Rect bounds(Iterable<Rect> boxes) =>
        boxes.reduce((a, b) => a.expandToInclude(b));

    Float64List filled(int count, double value) =>
        Float64List(count)..fillRange(0, count, value);

    test('ninguna caja pisa a otra, ni con tamaños distintos', () {
      final links = phoneLike();
      // Cajas de elemento y círculos de tema, de alturas distintas.
      final widths = Float64List.fromList(
        List.generate(27, (i) => i.isEven ? 150 : 96),
      );
      final heights = Float64List.fromList(
        List.generate(27, (i) => i % 3 == 0 ? 80 : 34),
      );

      final layout = layoutReadable(
        count: 27,
        links: links,
        widths: widths,
        heights: heights,
      );

      expect(overlaps(boxes(layout, widths, heights)), 0);
    });

    test('compacto: los componentes no se pierden lejos', () {
      final widths = filled(27, 150);
      final heights = filled(27, 34);
      final all = boxes(
        layoutReadable(count: 27, links: phoneLike()),
        widths,
        heights,
      );

      final area = bounds(all);
      var used = 0.0;
      for (final box in all) {
        used += box.width * box.height;
      }
      // Medido: el layout de fuerzas sobre el grafo entero ocupaba el 3 % de
      // su lienzo; este, el 14 %. La cota deja margen para ajustes finos sin
      // dejar volver el problema.
      expect(used / (area.width * area.height), greaterThan(0.08));
      // Los pares sueltos, cerca del grande: nada a miles de píxeles.
      expect(area.width, lessThan(1500));
      expect(area.height, lessThan(1500));
    });

    test('los componentes no se pisan entre sí: los separa el aire pedido', () {
      final widths = filled(27, 150);
      final heights = filled(27, 34);
      // El aire entre componentes por defecto es de 90.
      final layout = layoutReadable(count: 27, links: phoneLike());
      final all = boxes(layout, widths, heights);
      final big = bounds(all.sublist(0, 23));
      final pairA = bounds(all.sublist(23, 25));
      final pairB = bounds(all.sublist(25, 27));

      for (final (a, b) in [(big, pairA), (big, pairB), (pairA, pairB)]) {
        final gapX = math.max(a.left - b.right, b.left - a.right);
        final gapY = math.max(a.top - b.bottom, b.top - a.bottom);
        expect(math.max(gapX, gapY), greaterThanOrEqualTo(90 - 0.01));
      }
    });

    test('el componente más grande va primero, arriba a la izquierda', () {
      final layout = layoutReadable(count: 27, links: phoneLike());
      final widths = filled(27, 150);
      final heights = filled(27, 34);
      final all = boxes(layout, widths, heights);
      final big = bounds(all.sublist(0, 23));

      expect(big.top, closeTo(bounds(all).top, 0.01));
      expect(big.left, closeTo(bounds(all).left, 0.01));
    });

    test('dentro de un componente, lo unido queda más cerca que lo que no', () {
      final links = phoneLike().where((l) => l.a < 23).toList();
      final layout = layoutReadable(count: 23, links: links);
      final linked = {for (final l in links) (l.a, l.b)};
      final unlinked = [
        for (final pair in pairsWithin(List.generate(23, (i) => i)))
          if (!linked.contains(pair)) pair,
      ];

      expect(
        meanDistance(layout, linked),
        lessThan(meanDistance(layout, unlinked)),
      );
    });

    test('muchos sueltos van en filas, con la forma de la pantalla', () {
      // 20 pares sueltos: sin filas, quedarían en una sola línea interminable.
      final links = [
        for (var p = 0; p < 20; p++) MapLayoutLink(2 * p, 2 * p + 1, 1),
      ];
      final widths = filled(40, 150);
      final heights = filled(40, 34);

      final area = bounds(
        boxes(layoutReadable(count: 40, links: links), widths, heights),
      );

      // La proporción pedida es 0,75 (ancho sobre alto); las filas se llenan
      // de a componentes enteros, así que se pide estar en la zona.
      expect(area.width / area.height, inInclusiveRange(0.4, 1.4));
    });

    test('sin azar: el mismo grafo da exactamente el mismo layout', () {
      final a = layoutReadable(count: 27, links: phoneLike());
      final b = layoutReadable(count: 27, links: phoneLike());

      expect(a.xs, b.xs);
      expect(a.ys, b.ys);
    });

    test('recalcular desde lo que ya había casi no lo mueve', () {
      final first = layoutReadable(count: 27, links: phoneLike());
      final again = layoutReadable(
        count: 27,
        links: phoneLike(),
        startX: first.xs,
        startY: first.ys,
        iterations: 60,
      );

      // Menos que media caja: el mapa no salta al volver a la pantalla.
      expect(maxMove(first, again), lessThan(75));
    });

    test('sin nodos no hay nada, y uno solo queda en su lugar', () {
      expect(layoutReadable(count: 0, links: const []).count, 0);
      final single = layoutReadable(count: 1, links: const []);
      expect(single.xs.single.isFinite, isTrue);
    });
  });
}
