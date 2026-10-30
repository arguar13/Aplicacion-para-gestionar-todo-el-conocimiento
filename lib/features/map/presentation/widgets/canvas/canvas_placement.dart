import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/presentation/providers/map_layout_runner.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_node_size.dart';

/// Iteraciones del layout desde cero, y en caliente: con lo ya acomodado
/// alcanzan unas pocas.
const _kColdIterations = 260;
const _kWarmIterations = 60;

/// El aire alrededor de la red dentro del lienzo.
const _kCanvasMargin = 120.0;

/// Dónde va cada nodo de la red del lienzo (F18; F44, paso 2): lo que acomodó
/// el layout de fuerzas, ya dentro del lienzo y con margen, y lo que se
/// recuerda de cada nodo para que el próximo cálculo arranque en caliente.
///
/// No acomoda nada: arma el trabajo para el layout —que corre en otro
/// isolate— y guarda lo que vuelve.
class CanvasNetworkPlacement {
  /// Dónde va cada nodo, por su clave en la escena.
  Map<String, Offset> get positions => _positions;
  Map<String, Offset> _positions = {};

  /// Cuánto mide el lienzo con la red adentro.
  Size get canvas => _canvas;
  Size _canvas = Size.zero;

  /// La última posición de cada nodo, para arrancar en caliente.
  final Map<String, Offset> _remembered = {};

  /// Lo que el layout necesita para acomodar [scene]: en caliente ([warm]), lo
  /// que ya tenía lugar parte de él y alcanzan pocas iteraciones; lo nuevo
  /// parte de `NaN`, que el layout ubica.
  MapLayoutJob jobFor(GraphScene scene, {required bool warm}) {
    final startX = Float64List(scene.nodes.length);
    final startY = Float64List(scene.nodes.length);
    var known = 0;
    for (var i = 0; i < scene.nodes.length; i++) {
      final at = warm ? _remembered[scene.nodes[i].key] : null;
      startX[i] = at?.dx ?? double.nan;
      startY[i] = at?.dy ?? double.nan;
      if (at != null) known++;
    }
    final groups = Int32List(scene.nodes.length);
    for (var i = 0; i < groups.length; i++) {
      groups[i] = scene.nodes[i].group ?? -1 - i;
    }
    return (
      count: scene.nodes.length,
      links: scene.links,
      groups: groups,
      startX: known == 0 ? null : startX,
      startY: known == 0 ? null : startY,
      iterations: known == 0 ? _kColdIterations : _kWarmIterations,
      widths: Float64List.fromList([
        for (final node in scene.nodes) mapNodeSize(node).width,
      ]),
      heights: Float64List.fromList([
        for (final node in scene.nodes) mapNodeSize(node).height,
      ]),
    );
  }

  /// Guarda dónde quedó cada nodo de [scene] —[xs] e [ys], en su orden— y lo
  /// pone dentro del lienzo, con margen.
  void place(GraphScene scene, Float64List xs, Float64List ys) {
    _remembered.clear();
    if (xs.isEmpty) {
      _positions = {};
      _canvas = Size.zero;
      return;
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (var i = 0; i < xs.length; i++) {
      left = math.min(left, xs[i]);
      top = math.min(top, ys[i]);
      right = math.max(right, xs[i]);
      bottom = math.max(bottom, ys[i]);
      _remembered[scene.nodes[i].key] = Offset(xs[i], ys[i]);
    }
    final shift = Offset(_kCanvasMargin - left, _kCanvasMargin - top);
    _positions = {
      for (var i = 0; i < xs.length; i++)
        scene.nodes[i].key: Offset(xs[i], ys[i]) + shift,
    };
    _canvas = Size(
      right - left + 2 * _kCanvasMargin,
      bottom - top + 2 * _kCanvasMargin,
    );
  }
}
