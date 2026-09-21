import 'dart:math' as math;
import 'dart:ui';

/// Un nodo del esquema (F14, D6): un tema o una nota, con lo que cuelga de él.
///
/// El árbol que se le da a los layouts ya está armado y ya está recortado: lo
/// que el usuario no expandió es una hoja. Los layouts no saben qué es cada
/// nodo, solo cómo se agrupan.
class SchemaNode {
  const SchemaNode(this.id, {this.children = const []});

  final String id;
  final List<SchemaNode> children;
}

/// Dónde va cada nodo del esquema, con la raíz en el origen.
class SchemaLayout {
  const SchemaLayout(this.positions);

  final Map<String, Offset> positions;

  /// El rectángulo que ocupan los centros de los nodos.
  Rect get bounds {
    if (positions.isEmpty) return Rect.zero;
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final p in positions.values) {
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// El esquema como un árbol que va hacia un lado: la raíz al borde y cada nivel
/// en su columna —o en su fila—. Sirve para leerlo de arriba abajo, o de
/// izquierda a derecha.
enum SchemaDirection { down, right }

/// Cuántos nodos tiene el árbol de [root], contando cada identificador una
/// sola vez.
int schemaSize(SchemaNode root) => _flatten(root).length;

/// Aplana el árbol en preorden, sin repetir identificadores: un árbol de verdad
/// no los repite, pero uno armado de datos podría, y un ciclo no debe colgar
/// el dibujo.
List<({SchemaNode node, int depth, int parent})> _flatten(SchemaNode root) {
  final flat = <({SchemaNode node, int depth, int parent})>[];
  final seen = <String>{root.id};
  final stack = <({SchemaNode node, int depth, int parent})>[
    (node: root, depth: 0, parent: -1),
  ];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    final index = flat.length;
    flat.add(current);
    // Al revés, para que el primer hijo salga primero de la pila.
    for (final child in current.node.children.reversed) {
      if (seen.add(child.id)) {
        stack.add((node: child, depth: current.depth + 1, parent: index));
      }
    }
  }
  return flat;
}

/// El esquema radial: la raíz en el centro y cada nivel en un anillo. Cada
/// nodo se lleva del círculo un sector proporcional a sus hojas, así que las
/// ramas grandes tienen más lugar que las chicas, y sus hijos cuelgan en la
/// dirección del padre.
///
/// El radio de un anillo es el mayor entre [ringGap] más el del anillo
/// anterior y el que hace falta para que sus nodos, repartidos en la
/// circunferencia, no queden a menos de [minSpacing].
SchemaLayout layoutRadial(
  SchemaNode root, {
  double ringGap = 140,
  double minSpacing = 56,
}) {
  final flat = _flatten(root);
  final leaves = _leafCounts(flat);

  var maxDepth = 0;
  final perDepth = <int, int>{};
  for (final entry in flat) {
    maxDepth = math.max(maxDepth, entry.depth);
    perDepth.update(entry.depth, (n) => n + 1, ifAbsent: () => 1);
  }

  final radius = List<double>.filled(maxDepth + 1, 0);
  for (var depth = 1; depth <= maxDepth; depth++) {
    final crowded = perDepth[depth]! * minSpacing / (2 * math.pi);
    radius[depth] = math.max(radius[depth - 1] + ringGap, crowded);
  }

  // El sector de cada nodo: el del padre, repartido entre sus hijos según las
  // hojas de cada uno.
  final start = List<double>.filled(flat.length, 0);
  final end = List<double>.filled(flat.length, 2 * math.pi);
  final cursor = List<double>.filled(flat.length, 0);
  final positions = <String, Offset>{};
  for (var i = 0; i < flat.length; i++) {
    final entry = flat[i];
    if (entry.parent != -1) {
      final p = entry.parent;
      final span = (end[p] - start[p]) * leaves[i] / leaves[p];
      start[i] = cursor[p];
      end[i] = cursor[p] + span;
      cursor[p] = end[i];
    }
    cursor[i] = start[i];
    final angle = (start[i] + end[i]) / 2;
    final r = radius[entry.depth];
    positions[entry.node.id] = i == 0
        ? Offset.zero
        : Offset(r * math.cos(angle), r * math.sin(angle));
  }
  return SchemaLayout(positions);
}

/// El esquema como árbol: cada hoja en su lugar de la fila —separadas
/// [siblingGap]— y cada padre centrado sobre sus hijos; un nivel cada
/// [levelGap]. Con [direction] `down` los niveles bajan; con `right`, avanzan.
SchemaLayout layoutTree(
  SchemaNode root, {
  double levelGap = 120,
  double siblingGap = 64,
  SchemaDirection direction = SchemaDirection.down,
}) {
  final flat = _flatten(root);
  final along = List<double>.filled(flat.length, 0);
  final children = List.generate(flat.length, (_) => <int>[]);
  for (var i = 1; i < flat.length; i++) {
    children[flat[i].parent].add(i);
  }

  // El preorden pone a cada nodo antes que a sus hijos: al recorrerlo al
  // revés, los hijos ya tienen su lugar cuando les toca a los padres.
  var slot = 0;
  // Las hojas, de izquierda a derecha: el orden del preorden.
  for (var i = 0; i < flat.length; i++) {
    if (children[i].isEmpty) along[i] = (slot++) * siblingGap;
  }
  for (var i = flat.length - 1; i >= 0; i--) {
    if (children[i].isEmpty) continue;
    along[i] = (along[children[i].first] + along[children[i].last]) / 2;
  }

  final positions = <String, Offset>{};
  for (var i = 0; i < flat.length; i++) {
    final across = flat[i].depth * levelGap;
    positions[flat[i].node.id] = direction == SchemaDirection.down
        ? Offset(along[i], across)
        : Offset(across, along[i]);
  }
  return SchemaLayout(positions);
}

/// Cuántas hojas cuelgan de cada nodo, él incluido si es una: el peso de su
/// sector.
List<int> _leafCounts(List<({SchemaNode node, int depth, int parent})> flat) {
  final counts = List<int>.filled(flat.length, 0);
  for (var i = flat.length - 1; i >= 0; i--) {
    if (counts[i] == 0) counts[i] = 1;
    final parent = flat[i].parent;
    if (parent != -1) counts[parent] += counts[i];
  }
  return counts;
}
