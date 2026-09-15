import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/graph/domain/services/graph_view_fit.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

void main() {
  group('computeFitTransform', () {
    test('sin nodos, no hay nada que encuadrar', () {
      final matrix = computeFitTransform(
        positions: const {},
        viewportSize: const Size(400, 400),
      );

      expect(matrix, Matrix4.identity());
    });

    test('visor sin tamaño, tampoco hay nada que encuadrar', () {
      final matrix = computeFitTransform(
        positions: const {'a': Offset(10, 10)},
        viewportSize: Size.zero,
      );

      expect(matrix, Matrix4.identity());
    });

    test('centra el contenido en el centro del visor', () {
      final matrix = computeFitTransform(
        positions: const {'a': Offset(100, 100), 'b': Offset(300, 300)},
        viewportSize: const Size(800, 600),
        contentMargin: 0,
      );

      // El centro del contenido —el punto medio entre (100,100) y
      // (300,300)— tiene que caer exactamente en el centro del visor
      // después de aplicar la transformación.
      final center = matrix.transform3(Vector3(200, 200, 0));

      expect(center.x, closeTo(400, 0.001));
      expect(center.y, closeTo(300, 0.001));
    });

    test('escala para que todo el contenido entre, sin pasarse', () {
      // Con altura 0 —los dos puntos comparten la misma Y— y sin margen, el
      // contenido tendría alto cero: se le da un poco de margen para que la
      // caja de encuadre sea un rectángulo de verdad, no una línea.
      final matrix = computeFitTransform(
        positions: const {'a': Offset.zero, 'b': Offset(1000, 0)},
        viewportSize: const Size(500, 500),
        contentMargin: 10,
      );

      // El ancho del contenido (1000 + 2×10 de margen) tiene que quedar en,
      // como mucho, el ancho del visor (500).
      final left = matrix.transform3(Vector3.zero());
      final right = matrix.transform3(Vector3(1000, 0, 0));
      final renderedWidth = (right.x - left.x).abs();

      expect(renderedWidth, lessThanOrEqualTo(500.001));
    });

    test('no agranda de más un grafo minúsculo: respeta el techo de zoom', () {
      // Dos nodos separados por un solo píxel en un visor enorme agrandaría
      // la escala hasta un número absurdo si no hubiera techo.
      final matrix = computeFitTransform(
        positions: const {'a': Offset.zero, 'b': Offset(1, 0)},
        viewportSize: const Size(4000, 4000),
      );

      final scale = matrix.getMaxScaleOnAxis();
      expect(scale, closeTo(3, 0.001));
    });

    test('no achica de más un grafo enorme: respeta el piso de zoom', () {
      final matrix = computeFitTransform(
        positions: const {'a': Offset.zero, 'b': Offset(100000, 0)},
        viewportSize: const Size(400, 400),
      );

      final scale = matrix.getMaxScaleOnAxis();
      expect(scale, closeTo(0.1, 0.001));
    });

    test('un solo nodo no revienta por dividir entre un ancho cero', () {
      final matrix = computeFitTransform(
        positions: const {'a': Offset(50, 50)},
        viewportSize: const Size(400, 400),
        contentMargin: 0,
      );

      expect(matrix, Matrix4.identity());
    });
  });
}
