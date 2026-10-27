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

    test('con el piso que da zoomOutLimit, un grafo enorme entra entero', () {
      const positions = {'a': Offset.zero, 'b': Offset(100000, 0)};
      const viewport = Size(400, 400);

      final matrix = computeFitTransform(
        positions: positions,
        viewportSize: viewport,
        minScale: zoomOutLimit(positions: positions, viewportSize: viewport),
      );

      final left = matrix.transform3(Vector3(-70, 0, 0)).x;
      final right = matrix.transform3(Vector3(100070, 0, 0)).x;
      expect(left, greaterThanOrEqualTo(-0.001));
      expect(right, lessThanOrEqualTo(400.001));
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

  group('zoomOutLimit (F40)', () {
    test('un grafo chico se puede alejar hasta el piso de siempre', () {
      expect(
        zoomOutLimit(
          positions: const {'a': Offset.zero, 'b': Offset(300, 200)},
          viewportSize: const Size(400, 800),
        ),
        0.1,
      );
    });

    test('uno grande, hasta un poco más lejos de lo que lo encuadra', () {
      // 10.140 de ancho con el margen: entra en 400 a 400 / 10140.
      final limit = zoomOutLimit(
        positions: const {'a': Offset.zero, 'b': Offset(10000, 0)},
        viewportSize: const Size(400, 800),
      );

      expect(limit, closeTo(400 / 10140 * 0.8, 1e-9));
    });

    test('mira el lado que más aprieta', () {
      final limit = zoomOutLimit(
        positions: const {'a': Offset.zero, 'b': Offset(100, 20000)},
        viewportSize: const Size(400, 800),
        contentMargin: 0,
        slack: 1,
      );

      expect(limit, closeTo(800 / 20000, 1e-9));
    });

    test('sin nada que encuadrar, el piso', () {
      expect(
        zoomOutLimit(positions: const {}, viewportSize: const Size(400, 800)),
        0.1,
      );
      expect(
        zoomOutLimit(
          positions: const {'a': Offset(5, 5)},
          viewportSize: const Size(400, 800),
          contentMargin: 0,
        ),
        0.1,
      );
      expect(
        zoomOutLimit(
          positions: const {'a': Offset.zero, 'b': Offset(9000, 9000)},
          viewportSize: Size.zero,
        ),
        0.1,
      );
    });
  });
}
