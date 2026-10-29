import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// Un nodo que se acomoda: su tamaño ya medido y los que cuelgan de él. El
/// árbol que llega es el que se ve —lo de una rama cerrada no viene—.
@immutable
class TreeLayoutNode {
  const TreeLayoutNode(this.id, this.size, {this.children = const []});

  final String id;
  final Size size;
  final List<TreeLayoutNode> children;
}

/// Dónde va cada nodo del mapa, en un lienzo que empieza en el origen.
@immutable
class TreeLayout {
  const TreeLayout({
    required this.rects,
    required this.edges,
    required this.size,
  });

  /// El rectángulo de cada nodo, por su id.
  final Map<String, Rect> rects;

  /// Las uniones, de padre a hijo, en el orden en que se recorren.
  final List<(String parent, String child)> edges;

  /// Lo que ocupa todo, con su margen.
  final Size size;

  Rect? rectOf(String id) => rects[id];
}

/// El árbol horizontal del mapa mental (F43), como el de NotebookLM: la raíz
/// a la izquierda y cada nivel en su columna, a [levelGap] de la anterior; las
/// ramas de una idea, una debajo de otra, con la idea centrada a su altura.
///
/// Es un árbol ordenado («tidy tree») a la Reingold–Tilford para nodos de
/// tamaño distinto:
///
/// - cada subárbol se arma primero, y se guarda su **contorno** —lo más alto y
///   lo más bajo que ocupa en cada columna—;
/// - los subárboles hermanos se apilan lo más juntos que dejan sus contornos,
///   con [gap] entre lo que comparten una columna: un subárbol chico se mete
///   al lado de uno hondo sin dejar un hueco del alto de este;
/// - se apilan dos veces —de arriba abajo y de abajo arriba— y se toma el
///   promedio: así los hermanos chicos entre dos grandes quedan repartidos y
///   no pegados al primero. Cada apilado cumple todas las distancias entre
///   pares de hermanos, que son desigualdades lineales: el promedio también
///   las cumple, y **ningún par de nodos se toca**;
/// - cada idea queda centrada entre su primera y su última rama.
///
/// Como cada columna tiene el ancho de su nodo más ancho, dos nodos de
/// columnas distintas nunca se pisan; dos de la misma, lo evitan los
/// contornos.
TreeLayout layoutMindMapTree(
  TreeLayoutNode root, {
  double levelGap = 56,
  double gap = 12,
  EdgeInsets padding = const EdgeInsets.all(32),
}) {
  // El ancho de cada columna: el del nodo más ancho de ese nivel.
  final widths = <double>[];
  void measure(TreeLayoutNode node, int depth) {
    if (widths.length <= depth) widths.add(0);
    widths[depth] = math.max(widths[depth], node.size.width);
    for (final child in node.children) {
      measure(child, depth + 1);
    }
  }

  measure(root, 0);
  final columnLeft = <double>[];
  var x = padding.left;
  for (final width in widths) {
    columnLeft.add(x);
    x += width + levelGap;
  }

  final placed = _place(root, gap);
  final rects = <String, Rect>{};
  final edges = <(String, String)>[];
  var top = double.infinity;
  var bottom = double.negativeInfinity;
  void absolute(_Placed placed, double y, int depth) {
    final node = placed.node;
    final rect = Rect.fromLTWH(
      columnLeft[depth],
      y,
      node.size.width,
      node.size.height,
    );
    rects[node.id] = rect;
    top = math.min(top, rect.top);
    bottom = math.max(bottom, rect.bottom);
    for (final (i, child) in placed.children.indexed) {
      edges.add((node.id, child.node.id));
      absolute(child, y + placed.offsets[i], depth + 1);
    }
  }

  absolute(placed, 0, 0);
  // Se corre el dibujo entero para que lo más alto quede en el margen.
  final shift = padding.top - top;
  final shifted = {
    for (final entry in rects.entries)
      entry.key: entry.value.shift(Offset(0, shift)),
  };
  final width = x - levelGap + padding.right;
  final height = bottom - top + padding.vertical;
  return TreeLayout(rects: shifted, edges: edges, size: Size(width, height));
}

/// Un subárbol ya armado: su nodo arriba de todo (en 0), dónde va cada rama
/// respecto de él y su contorno.
class _Placed {
  _Placed(this.node, this.children, this.offsets, this.tops, this.bottoms);

  final TreeLayoutNode node;
  final List<_Placed> children;

  /// Lo que se baja cada rama respecto del borde de arriba del nodo.
  final List<double> offsets;

  /// Lo más alto y lo más bajo del subárbol en cada nivel, desde el suyo.
  final List<double> tops;
  final List<double> bottoms;
}

_Placed _place(TreeLayoutNode node, double gap) {
  final height = node.size.height;
  if (node.children.isEmpty) {
    return _Placed(node, const [], const [], [0], [height]);
  }
  final children = [for (final child in node.children) _place(child, gap)];
  final n = children.length;

  // De arriba abajo: cada rama, justo debajo de todo lo anterior, nivel por
  // nivel.
  final down = List<double>.filled(n, 0);
  final reach = <double>[...children.first.bottoms];
  for (var i = 1; i < n; i++) {
    final child = children[i];
    var offset = double.negativeInfinity;
    for (var l = 0; l < child.tops.length && l < reach.length; l++) {
      offset = math.max(offset, reach[l] + gap - child.tops[l]);
    }
    down[i] = offset;
    for (var l = 0; l < child.bottoms.length; l++) {
      final b = offset + child.bottoms[l];
      if (l < reach.length) {
        reach[l] = math.max(reach[l], b);
      } else {
        reach.add(b);
      }
    }
  }

  // De abajo arriba: lo mismo desde la última.
  final up = List<double>.filled(n, 0);
  final floor = <double>[...children.last.tops];
  for (var i = n - 2; i >= 0; i--) {
    final child = children[i];
    var offset = double.infinity;
    for (var l = 0; l < child.bottoms.length && l < floor.length; l++) {
      offset = math.min(offset, floor[l] - gap - child.bottoms[l]);
    }
    up[i] = offset;
    for (var l = 0; l < child.tops.length; l++) {
      final t = offset + child.tops[l];
      if (l < floor.length) {
        floor[l] = math.min(floor[l], t);
      } else {
        floor.add(t);
      }
    }
  }

  // El promedio de los dos, con la primera rama en el mismo lugar.
  final base = up.first;
  final offsets = [for (var i = 0; i < n; i++) (down[i] + up[i] - base) / 2];

  // La idea, centrada entre el centro de su primera rama y el de la última.
  final first = offsets.first + children.first.node.size.height / 2;
  final last = offsets.last + children.last.node.size.height / 2;
  final lift = (first + last) / 2 - height / 2;
  for (var i = 0; i < n; i++) {
    offsets[i] -= lift;
  }

  final tops = <double>[0];
  final bottoms = <double>[height];
  for (final (i, child) in children.indexed) {
    for (var l = 0; l < child.tops.length; l++) {
      final t = offsets[i] + child.tops[l];
      final b = offsets[i] + child.bottoms[l];
      if (l + 1 < tops.length) {
        tops[l + 1] = math.min(tops[l + 1], t);
        bottoms[l + 1] = math.max(bottoms[l + 1], b);
      } else {
        tops.add(t);
        bottoms.add(b);
      }
    }
  }
  return _Placed(node, children, offsets, tops, bottoms);
}
