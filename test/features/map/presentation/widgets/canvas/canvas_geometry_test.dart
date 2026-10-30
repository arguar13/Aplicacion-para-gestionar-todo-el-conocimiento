import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_motion.dart';
import 'package:sinapsis/features/map/presentation/widgets/canvas/canvas_viewport.dart';

/// Las cuentas del lienzo único (F44, paso 2): qué parte se ve, cómo acercan
/// ⊕ y ⊖, adónde lleva el minimapa y cómo se mueve un cambio de altura.
void main() {
  Matrix4 view(double scale, Offset translation) => Matrix4.identity()
    ..translateByDouble(translation.dx, translation.dy, 0, 1)
    ..scaleByDouble(scale, scale, scale, 1);

  group('lo que se ve', () {
    test(
      'con zoom 2 y corrido, se ve la mitad del visor desde donde arranca',
      () {
        final visible = visibleSceneRect(
          view(2, const Offset(-100, -40)),
          const Size(400, 300),
        );

        expect(visible.left, closeTo(50, 1e-9));
        expect(visible.top, closeTo(20, 1e-9));
        expect(visible.width, closeTo(200, 1e-9));
        expect(visible.height, closeTo(150, 1e-9));
      },
    );

    test('se ve todo si el contenido entra en lo visible; si no, no', () {
      const content = Rect.fromLTWH(10, 10, 100, 100);

      expect(showsWhole(const Rect.fromLTWH(0, 0, 200, 200), content), isTrue);
      expect(
        showsWhole(const Rect.fromLTWH(50, 0, 200, 200), content),
        isFalse,
      );
      expect(showsWhole(const Rect.fromLTWH(0, 0, 10, 10), Rect.zero), isTrue);
    });

    test('el contenido es lo que ocupan los nodos, con su margen', () {
      final bounds = contentBounds(const [
        Offset(10, 20),
        Offset(50, 5),
      ], margin: 5);

      expect(bounds, const Rect.fromLTRB(5, 0, 55, 25));
      expect(contentBounds(const []), Rect.zero);
    });
  });

  group('⊕ y ⊖', () {
    test(
      'acercar deja quieto lo que está bajo el punto, y respeta el tope',
      () {
        const focal = Offset(200, 150);
        final start = view(1, const Offset(-30, 10));
        final before = MatrixUtils.transformPoint(
          Matrix4.inverted(start),
          focal,
        );

        final zoomed = zoomAround(
          start,
          kCanvasZoomStep,
          focal,
          minScale: 0.05,
          maxScale: 4,
        );
        final after = MatrixUtils.transformPoint(
          Matrix4.inverted(zoomed),
          focal,
        );

        expect(zoomed.getMaxScaleOnAxis(), closeTo(kCanvasZoomStep, 1e-9));
        expect((after - before).distance, lessThan(1e-6));
        expect(
          zoomAround(
            view(3.5, Offset.zero),
            kCanvasZoomStep,
            focal,
            minScale: 0.05,
            maxScale: 4,
          ).getMaxScaleOnAxis(),
          closeTo(4, 1e-9),
        );
        expect(
          zoomAround(
            view(0.06, Offset.zero),
            1 / kCanvasZoomStep,
            focal,
            minScale: 0.05,
            maxScale: 4,
          ).getMaxScaleOnAxis(),
          closeTo(0.05, 1e-9),
        );
      },
    );

    test(
      'centrar en un punto lo lleva al medio del visor con el mismo zoom',
      () {
        const viewport = Size(400, 300);
        final centered = centerOn(
          view(2, const Offset(7, 9)),
          const Offset(500, 120),
          viewport,
        );

        expect(centered.getMaxScaleOnAxis(), closeTo(2, 1e-9));
        final middle = MatrixUtils.transformPoint(
          Matrix4.inverted(centered),
          viewport.center(Offset.zero),
        );
        expect((middle - const Offset(500, 120)).distance, lessThan(1e-6));
      },
    );
  });

  group('el minimapa', () {
    test(
      'el contenido entra entero y centrado, y se vuelve al mismo punto',
      () {
        final geometry = MinimapGeometry(
          const Rect.fromLTWH(100, 100, 400, 200),
          const Size(120, 90),
        );

        expect(geometry.scale, closeTo(0.3, 1e-9));
        // 400 × 200 achicado es 120 × 60: sobran 30 de alto, 15 arriba.
        expect(geometry.toMinimap(const Offset(100, 100)), const Offset(0, 15));
        final back = geometry.toScene(
          geometry.toMinimap(const Offset(320, 250)),
        );
        expect((back - const Offset(320, 250)).distance, lessThan(1e-9));
      },
    );
  });

  group('el movimiento entre alturas', () {
    const to = {'a': Offset(100, 0), 'b': Offset(0, 100)};

    test('salir de la burbuja: todo nace en el origen y llega a su lugar', () {
      final motion = CanvasMotion.emerge(const Offset(10, 10), to);

      expect(motion.positionsAt(0), {
        'a': const Offset(10, 10),
        'b': const Offset(10, 10),
      });
      expect(motion.positionsAt(1), to);
      expect(motion.positionsAt(0.5)['a'], const Offset(55, 5));
      expect(motion.opacityAt(0), 0);
      expect(motion.opacityAt(1), 1);
    });

    test('recoger: todo va a su centro y se apaga', () {
      final motion = CanvasMotion.collapse(to);

      expect(motion.positionsAt(1), {
        'a': const Offset(50, 50),
        'b': const Offset(50, 50),
      });
      expect(motion.positionsAt(0), to);
      expect(motion.opacityAt(0), 1);
      expect(motion.opacityAt(1), 0);
    });

    test('aparecer: quieto, y se enciende', () {
      final motion = CanvasMotion.fadeIn(to);

      expect(motion.positionsAt(0.3), to);
      expect(motion.opacityAt(0.3), closeTo(0.3, 1e-9));
    });
  });
}
