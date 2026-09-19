import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';

/// El algoritmo tal como era ANTES de pasarlo a arreglos: sobre un mapa de id
/// a `Offset`. Se conserva acá como referencia para demostrar que la versión
/// rápida da exactamente lo mismo, no algo parecido.
Map<String, Offset> _referenceLayout({
  required List<String> nodeIds,
  required List<(String, String)> edges,
  Size canvasSize = const Size(900, 900),
  int iterations = 300,
}) {
  if (nodeIds.isEmpty) return {};
  if (nodeIds.length == 1) {
    return {nodeIds.single: canvasSize.center(Offset.zero)};
  }

  final area = canvasSize.width * canvasSize.height;
  final k = math.sqrt(area / nodeIds.length);

  final positions = <String, Offset>{
    for (var i = 0; i < nodeIds.length; i++)
      nodeIds[i]:
          canvasSize.center(Offset.zero) +
          Offset.fromDirection(
            2 * math.pi * i / nodeIds.length,
            math.min(canvasSize.width, canvasSize.height) / 3,
          ),
  };

  var temperature = canvasSize.width / 10;

  for (var iteration = 0; iteration < iterations; iteration++) {
    final displacement = {for (final id in nodeIds) id: Offset.zero};

    for (var i = 0; i < nodeIds.length; i++) {
      for (var j = i + 1; j < nodeIds.length; j++) {
        final a = nodeIds[i];
        final b = nodeIds[j];
        final delta = positions[a]! - positions[b]!;
        final distance = math.max(delta.distance, 0.01);
        final force = (k * k) / distance;
        final direction = delta / distance;

        displacement[a] = displacement[a]! + direction * force;
        displacement[b] = displacement[b]! - direction * force;
      }
    }

    for (final (from, to) in edges) {
      if (!positions.containsKey(from) || !positions.containsKey(to)) {
        continue;
      }
      final delta = positions[from]! - positions[to]!;
      final distance = math.max(delta.distance, 0.01);
      final force = (distance * distance) / k;
      final direction = delta / distance;

      displacement[from] = displacement[from]! - direction * force;
      displacement[to] = displacement[to]! + direction * force;
    }

    for (final id in nodeIds) {
      final disp = displacement[id]!;
      final distance = math.max(disp.distance, 0.01);
      final capped = disp / distance * math.min(distance, temperature);

      positions[id] = positions[id]! + capped;
    }

    temperature *= 0.97;
  }

  return positions;
}

void main() {
  group('computeGraphLayout', () {
    test('un solo nodo va al centro del lienzo', () {
      final positions = computeGraphLayout(
        nodeIds: ['a'],
        edges: const [],
        canvasSize: const Size(400, 400),
      );

      expect(positions, {'a': const Offset(200, 200)});
    });

    test('una lista vacía no produce ninguna posición', () {
      expect(computeGraphLayout(nodeIds: const [], edges: const []), isEmpty);
    });

    test('cada nodo termina en una posición finita, sin números raros', () {
      final positions = computeGraphLayout(
        nodeIds: ['a', 'b', 'c', 'd', 'e'],
        edges: const [('a', 'b'), ('b', 'c')],
        canvasSize: const Size(500, 500),
      );

      expect(positions.keys, unorderedEquals(['a', 'b', 'c', 'd', 'e']));
      for (final position in positions.values) {
        expect(position.dx.isFinite, isTrue);
        expect(position.dy.isFinite, isTrue);
      }
    });

    test('sin ningún vínculo que los atraiga de vuelta, muchos nodos se '
        'separan más que el lienzo de partida: ya no quedan atrapados en un '
        'rectángulo fijo', () {
      // Sin aristas, la repulsión entre nodos sueltos no tiene nada que
      // la contrarreste: antes, el clamp duro los frenaba en el borde de
      // `canvasSize`; ahora se separan lo que la física del layout pide.
      final nodeIds = [for (var i = 0; i < 12; i++) 'n$i'];
      final positions = computeGraphLayout(
        nodeIds: nodeIds,
        edges: const [],
        canvasSize: const Size(300, 300),
      );

      const center = Offset(150, 150);
      final maxDistance = positions.values
          .map((p) => (p - center).distance)
          .reduce(math.max);

      // La mitad de la diagonal de un lienzo de 300x300 es ~212: que
      // algún nodo termine más lejos que eso del centro demuestra que el
      // layout puede crecer más allá del rectángulo de partida.
      expect(maxDistance, greaterThan(212));
    });

    test('dos nodos vinculados terminan más cerca que dos que no lo están', () {
      // "a" y "b" están conectados; "c" queda suelto. Un layout de verdad
      // —no una disposición arbitraria— tiene que acercar a los primeros
      // dos más que a cualquiera de ellos con el tercero.
      final positions = computeGraphLayout(
        nodeIds: ['a', 'b', 'c'],
        edges: const [('a', 'b')],
        canvasSize: const Size(600, 600),
      );

      final distanceAB = (positions['a']! - positions['b']!).distance;
      final distanceAC = (positions['a']! - positions['c']!).distance;
      final distanceBC = (positions['b']! - positions['c']!).distance;

      expect(distanceAB, lessThan(distanceAC));
      expect(distanceAB, lessThan(distanceBC));
    });

    test('es determinístico: la misma entrada da siempre la misma salida', () {
      final first = computeGraphLayout(
        nodeIds: ['a', 'b', 'c', 'd'],
        edges: const [('a', 'b'), ('c', 'd')],
      );
      final second = computeGraphLayout(
        nodeIds: ['a', 'b', 'c', 'd'],
        edges: const [('a', 'b'), ('c', 'd')],
      );

      expect(first, second);
    });

    test('da exactamente lo mismo que el algoritmo sobre mapas, en grafos '
        'de cualquier forma', () {
      final random = math.Random(11);
      for (final size in [2, 3, 7, 25, 60]) {
        final ids = [for (var i = 0; i < size; i++) 'nodo-$i'];
        final edges = <(String, String)>[
          for (var i = 0; i < size * 2; i++)
            (ids[random.nextInt(size)], ids[random.nextInt(size)]),
          // Una arista hacia algo que no es un nodo, y una repetida.
          (ids.first, 'fantasma'),
          (ids.first, ids.last),
          (ids.first, ids.last),
        ];

        final actual = computeGraphLayout(nodeIds: ids, edges: edges);
        final expected = _referenceLayout(nodeIds: ids, edges: edges);

        expect(actual.keys.toList(), expected.keys.toList());
        for (final id in ids) {
          expect(actual[id], expected[id], reason: 'nodo $id, tamaño $size');
        }
      }
    });

    test('también con otro lienzo y otra cantidad de vueltas', () {
      final ids = [for (var i = 0; i < 12; i++) 'n$i'];
      final edges = [for (var i = 1; i < 12; i++) (ids[i - 1], ids[i])];
      const canvas = Size(360, 240);

      final actual = computeGraphLayout(
        nodeIds: ids,
        edges: edges,
        canvasSize: canvas,
        iterations: 150,
      );
      final expected = _referenceLayout(
        nodeIds: ids,
        edges: edges,
        canvasSize: canvas,
        iterations: 150,
      );

      expect(actual, expected);
    });

    test('una arista hacia un nodo que no existe no rompe el cálculo', () {
      expect(
        () => computeGraphLayout(
          nodeIds: ['a', 'b'],
          edges: const [('a', 'no-existe')],
        ),
        returnsNormally,
      );
    });
  });
}
