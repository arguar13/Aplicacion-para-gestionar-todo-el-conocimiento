import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/mind_map/presentation/mind_map_scene.dart';

/// F43, paso 9: cómo se mira el mapa —encuadrarlo y acercarlo—. El visor lee
/// la escala con `getMaxScaleOnAxis`, así que la escala va en los tres ejes.
void main() {
  test('encuadrar un mapa grande: lo aleja hasta que entra, centrado', () {
    final m = mindMapFitTransform(
      const Size(2000, 1000),
      const Size(400, 400),
      minScale: 0.1,
    );
    const scale = 400 / 2000 * 0.94;
    expect(m.getMaxScaleOnAxis(), closeTo(scale, 1e-9));
    final topLeft = MatrixUtils.transformPoint(m, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(m, const Offset(2000, 1000));
    expect(topLeft.dx, closeTo(400 - bottomRight.dx, 1e-9));
    expect(topLeft.dy, closeTo(400 - bottomRight.dy, 1e-9));
  });

  test('un mapa chico no se agranda de más, ni se aleja menos del piso', () {
    expect(
      mindMapFitTransform(
        const Size(100, 100),
        const Size(400, 400),
        minScale: 0.1,
      ).getMaxScaleOnAxis(),
      1,
    );
    expect(
      mindMapFitTransform(
        const Size(100000, 100),
        const Size(400, 400),
        minScale: 0.15,
      ).getMaxScaleOnAxis(),
      closeTo(0.15, 1e-9),
    );
  });

  test('acercar desde un encuadre lejano multiplica la escala de verdad, '
      'alrededor del punto pedido', () {
    final fit = mindMapFitTransform(
      const Size(2000, 1000),
      const Size(400, 400),
      minScale: 0.1,
    );
    const focal = Offset(200, 200);
    final before = MatrixUtils.transformPoint(Matrix4.inverted(fit), focal);
    final zoomed = mindMapZoomTransform(
      fit,
      2,
      focal,
      minScale: 0.1,
      maxScale: 3,
    );
    expect(
      zoomed.getMaxScaleOnAxis(),
      closeTo(fit.getMaxScaleOnAxis() * 2, 1e-9),
    );
    // El punto del mapa que estaba bajo el foco, sigue ahí.
    final after = MatrixUtils.transformPoint(zoomed, before);
    expect(after.dx, closeTo(200, 1e-6));
    expect(after.dy, closeTo(200, 1e-6));
    // Con tope.
    expect(
      mindMapZoomTransform(
        fit,
        100,
        focal,
        minScale: 0.1,
        maxScale: 3,
      ).getMaxScaleOnAxis(),
      closeTo(3, 1e-9),
    );
  });

  test('alejar también se lee como alejado: la escala va en los tres ejes', () {
    final away = mindMapZoomTransform(
      Matrix4.identity(),
      0.5,
      Offset.zero,
      minScale: 0.1,
      maxScale: 3,
    );
    expect(away.getMaxScaleOnAxis(), closeTo(0.5, 1e-9));
    // Y desde ahí, acercar vuelve a 1.
    expect(
      mindMapZoomTransform(
        away,
        2,
        Offset.zero,
        minScale: 0.1,
        maxScale: 3,
      ).getMaxScaleOnAxis(),
      closeTo(1, 1e-9),
    );
  });
}
