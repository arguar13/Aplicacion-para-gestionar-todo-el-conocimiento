import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/graph/presentation/widgets/graph_edges_painter.dart';

void main() {
  group('clipToRectBorder', () {
    const center = Offset(100, 100);
    const halfWidth = 60.0;
    const halfHeight = 20.0;

    test('un rayo hacia la derecha toca la pared vertical', () {
      final point = clipToRectBorder(
        center,
        const Offset(1, 0),
        halfWidth,
        halfHeight,
      );

      expect(point, const Offset(160, 100));
    });

    test('un rayo hacia arriba toca la pared horizontal', () {
      final point = clipToRectBorder(
        center,
        const Offset(0, -1),
        halfWidth,
        halfHeight,
      );

      expect(point, const Offset(100, 80));
    });

    test(
      'un rayo en diagonal toca la pared que está más cerca, no la otra',
      () {
        // Una tarjeta ancha y baja: yendo en diagonal a 45°, la pared de
        // arriba —mucho más cerca del centro que la de los costados—
        // tiene que ser la que se cruza primero.
        final point = clipToRectBorder(
          center,
          const Offset(0.7071, -0.7071),
          halfWidth,
          halfHeight,
        );

        expect(point.dy, closeTo(80, 0.01));
        expect(point.dx, greaterThan(100));
        expect(point.dx, lessThan(160));
      },
    );

    test('el punto siempre cae sobre el borde, nunca más allá', () {
      for (final angle in [0.0, 0.3, 0.9, 1.5, 2.4, 3.1, 4.0, 5.5]) {
        final unit = Offset(math.cos(angle), math.sin(angle));
        final point = clipToRectBorder(center, unit, halfWidth, halfHeight);
        final relative = point - center;

        expect(relative.dx.abs(), lessThanOrEqualTo(halfWidth + 0.001));
        expect(relative.dy.abs(), lessThanOrEqualTo(halfHeight + 0.001));
        // Toca alguna de las dos paredes de verdad, no queda adentro.
        final onVerticalWall = (relative.dx.abs() - halfWidth).abs() < 0.01;
        final onHorizontalWall = (relative.dy.abs() - halfHeight).abs() < 0.01;
        expect(onVerticalWall || onHorizontalWall, isTrue);
      }
    });
  });
}
