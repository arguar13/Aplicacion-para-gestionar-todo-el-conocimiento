import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Cuánto acercan y alejan ⊕ y ⊖ por toque (F44, paso 2).
const kCanvasZoomStep = 1.5;

/// La parte del lienzo que se ve en un visor de [viewport] con [transform].
Rect visibleSceneRect(Matrix4 transform, Size viewport) {
  final inverse = Matrix4.inverted(transform);
  final a = MatrixUtils.transformPoint(inverse, Offset.zero);
  final b = MatrixUtils.transformPoint(
    inverse,
    Offset(viewport.width, viewport.height),
  );
  return Rect.fromPoints(a, b);
}

/// [current] acercado [factor] veces alrededor de [focal] —un punto del
/// visor—, sin pasar de [minScale] ni de [maxScale]: lo que está bajo [focal]
/// queda ahí.
Matrix4 zoomAround(
  Matrix4 current,
  double factor,
  Offset focal, {
  required double minScale,
  required double maxScale,
}) {
  final scale = current.getMaxScaleOnAxis();
  final target = (scale * factor).clamp(minScale, maxScale);
  final step = target / scale;
  return Matrix4.identity()
    ..translateByDouble(focal.dx, focal.dy, 0, 1)
    ..scaleByDouble(step, step, step, 1)
    ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
    ..multiply(current);
}

/// [current] corrido para que [scenePoint] quede en el centro de un visor de
/// [viewport], con el mismo zoom: lo que hace tocar el minimapa.
Matrix4 centerOn(Matrix4 current, Offset scenePoint, Size viewport) {
  final scale = current.getMaxScaleOnAxis();
  return Matrix4.identity()
    ..translateByDouble(
      viewport.width / 2 - scenePoint.dx * scale,
      viewport.height / 2 - scenePoint.dy * scale,
      0,
      1,
    )
    ..scaleByDouble(scale, scale, scale, 1);
}

/// El rectángulo que ocupan [positions], agrandado [margin] de cada lado:
/// lo dibujado, sin el aire del lienzo. Vacío si no hay nada.
Rect contentBounds(Iterable<Offset> positions, {double margin = 0}) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final p in positions) {
    left = math.min(left, p.dx);
    top = math.min(top, p.dy);
    right = math.max(right, p.dx);
    bottom = math.max(bottom, p.dy);
  }
  if (left == double.infinity) return Rect.zero;
  return Rect.fromLTRB(left, top, right, bottom).inflate(margin);
}

/// Si con [visible] a la vista se ve todo [content]: entonces el minimapa no
/// tiene nada que decir y se esconde.
bool showsWhole(Rect visible, Rect content) {
  if (content.isEmpty) return true;
  // Medio píxel de tolerancia: el encuadre redondea.
  return visible.inflate(0.5).contains(content.topLeft) &&
      visible.inflate(0.5).contains(content.bottomRight);
}

/// Cómo se pasa de un punto del lienzo a uno del minimapa y de vuelta: el
/// contenido entero, achicado para caber en el minimapa y centrado en él.
class MinimapGeometry {
  factory MinimapGeometry(Rect content, Size minimap) {
    if (content.isEmpty || minimap.isEmpty) {
      return MinimapGeometry._(content, 1, Offset.zero);
    }
    final scale = math.min(
      minimap.width / content.width,
      minimap.height / content.height,
    );
    final drawn = Size(content.width * scale, content.height * scale);
    final offset = Offset(
      (minimap.width - drawn.width) / 2,
      (minimap.height - drawn.height) / 2,
    );
    return MinimapGeometry._(content, scale, offset);
  }

  const MinimapGeometry._(this.content, this.scale, this.offset);

  /// Lo que el minimapa resume, en coordenadas del lienzo.
  final Rect content;

  /// Cuánto se achica el lienzo en el minimapa.
  final double scale;

  /// Dónde empieza el contenido dentro del minimapa.
  final Offset offset;

  Offset toMinimap(Offset scenePoint) =>
      offset + (scenePoint - content.topLeft) * scale;

  Offset toScene(Offset minimapPoint) =>
      content.topLeft + (minimapPoint - offset) / scale;

  Rect rectToMinimap(Rect scene) =>
      Rect.fromPoints(toMinimap(scene.topLeft), toMinimap(scene.bottomRight));
}
