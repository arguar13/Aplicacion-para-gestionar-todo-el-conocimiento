import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/graph/domain/services/graph_layout.dart';

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

    test('cada nodo termina con una posición dentro del lienzo', () {
      final positions = computeGraphLayout(
        nodeIds: ['a', 'b', 'c', 'd', 'e'],
        edges: const [('a', 'b'), ('b', 'c')],
        canvasSize: const Size(500, 500),
      );

      expect(positions.keys, unorderedEquals(['a', 'b', 'c', 'd', 'e']));
      for (final position in positions.values) {
        expect(position.dx, inInclusiveRange(0, 500));
        expect(position.dy, inInclusiveRange(0, 500));
      }
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
