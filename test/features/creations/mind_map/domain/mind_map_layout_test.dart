import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/mind_map/domain/mind_map_layout.dart';

/// F43, paso 9: el árbol horizontal del mapa mental. Lo que no puede pasar
/// nunca —con cualquier árbol y cualquier tamaño de nodo— es que dos nodos
/// se pisen; y cada idea va a la derecha de la de arriba, centrada entre
/// sus ramas.
void main() {
  /// Un árbol al azar de [seed]: hasta [maxNodes] nodos, con ramas de 0 a
  /// [maxChildren] y tamaños como los de un nodo de verdad —de un renglón
  /// corto a tres renglones anchos—.
  TreeLayoutNode randomTree(
    int seed, {
    int maxNodes = 120,
    int maxChildren = 6,
  }) {
    final random = math.Random(seed);
    var count = 0;
    Size size() => Size(
      60 + random.nextDouble() * 200,
      44 + random.nextInt(3) * 20 + random.nextDouble() * 4,
    );
    TreeLayoutNode grow(String id, int depth) {
      count++;
      final children = <TreeLayoutNode>[];
      final wanted = depth > 5 ? 0 : random.nextInt(maxChildren + 1);
      for (var i = 0; i < wanted && count < maxNodes; i++) {
        children.add(grow('$id.$i', depth + 1));
      }
      return TreeLayoutNode(id, size(), children: children);
    }

    return grow('0', 0);
  }

  Iterable<TreeLayoutNode> all(TreeLayoutNode node) sync* {
    yield node;
    for (final child in node.children) {
      yield* all(child);
    }
  }

  group('con cualquier árbol (300 al azar)', () {
    for (var seed = 0; seed < 300; seed++) {
      test('semilla $seed: ningún par de nodos se pisa, cada rama a la '
          'derecha y la idea centrada entre sus ramas', () {
        final tree = randomTree(seed, maxChildren: 1 + seed % 8);
        const gap = 12.0; // el de siempre de `layoutMindMapTree`
        final layout = layoutMindMapTree(tree);
        final nodes = all(tree).toList();
        expect(layout.rects.keys.toSet(), {for (final n in nodes) n.id});

        final rects = [for (final n in nodes) layout.rects[n.id]!];
        for (var i = 0; i < rects.length; i++) {
          // Del tamaño medido.
          expect(rects[i].width, closeTo(nodes[i].size.width, 1e-6));
          expect(rects[i].height, closeTo(nodes[i].size.height, 1e-6));
          // Dentro del lienzo.
          expect(rects[i].left, greaterThanOrEqualTo(0));
          expect(rects[i].top, greaterThanOrEqualTo(0));
          expect(rects[i].right, lessThanOrEqualTo(layout.size.width + 1e-6));
          expect(rects[i].bottom, lessThanOrEqualTo(layout.size.height + 1e-6));
          for (var j = i + 1; j < rects.length; j++) {
            // Con el aire de [gap] entre los de una misma columna, menos un
            // margen por los redondeos.
            final a = rects[i].inflate(gap / 2 - 0.01);
            final b = rects[j].inflate(gap / 2 - 0.01);
            final sameColumn = rects[i].left == rects[j].left;
            expect(
              sameColumn ? a.overlaps(b) : rects[i].overlaps(rects[j]),
              isFalse,
              reason: '${nodes[i].id} y ${nodes[j].id} se pisan',
            );
          }
        }

        for (final node in nodes) {
          if (node.children.isEmpty) continue;
          final parent = layout.rects[node.id]!;
          for (final child in node.children) {
            expect(
              layout.rects[child.id]!.left,
              greaterThan(parent.right),
              reason: '${child.id} no está a la derecha de ${node.id}',
            );
          }
          final first = layout.rects[node.children.first.id]!.center.dy;
          final last = layout.rects[node.children.last.id]!.center.dy;
          expect(parent.center.dy, closeTo((first + last) / 2, 1e-6));
          // Las ramas, en su orden, de arriba abajo.
          for (var k = 1; k < node.children.length; k++) {
            expect(
              layout.rects[node.children[k].id]!.top,
              greaterThan(layout.rects[node.children[k - 1].id]!.top),
            );
          }
        }
      });
    }
  });

  test('cada nivel en su columna, a levelGap de la anterior', () {
    const tree = TreeLayoutNode(
      'r',
      Size(100, 40),
      children: [
        TreeLayoutNode(
          'a',
          Size(160, 40),
          children: [TreeLayoutNode('a1', Size(80, 40))],
        ),
        TreeLayoutNode(
          'b',
          Size(60, 40),
          children: [TreeLayoutNode('b1', Size(90, 40))],
        ),
      ],
    );
    final layout = layoutMindMapTree(tree, levelGap: 50);
    expect(layout.rects['r']!.left, 32);
    expect(layout.rects['a']!.left, 32 + 100 + 50);
    expect(layout.rects['b']!.left, 32 + 100 + 50);
    // La columna de los nietos empieza después del más ancho de los hijos.
    expect(layout.rects['a1']!.left, 32 + 100 + 50 + 160 + 50);
    expect(layout.rects['b1']!.left, layout.rects['a1']!.left);
    expect(layout.size.width, 32 + 100 + 50 + 160 + 50 + 90 + 32);
    expect(layout.edges, [('r', 'a'), ('a', 'a1'), ('r', 'b'), ('b', 'b1')]);
  });

  test('un subárbol chico se mete al lado de uno hondo, sin un hueco del '
      'alto de este', () {
    // «a» tiene muchas hojas abajo; «b», ninguna: «b» puede ir pegado a «a»
    // en su columna aunque las hojas de «a» bajen más.
    final tree = TreeLayoutNode(
      'r',
      const Size(80, 40),
      children: [
        TreeLayoutNode(
          'a',
          const Size(80, 40),
          children: [
            for (var i = 0; i < 9; i++)
              TreeLayoutNode('a$i', const Size(80, 40)),
          ],
        ),
        const TreeLayoutNode('b', Size(80, 40)),
      ],
    );
    final layout = layoutMindMapTree(tree, gap: 10);
    final a = layout.rects['a']!;
    final b = layout.rects['b']!;
    final lastLeaf = layout.rects['a8']!;
    // «a» está centrado sobre sus nueve hojas (450 de alto): «b» va justo
    // debajo de «a», muy por encima de la última hoja.
    expect(b.top - a.bottom, closeTo(10, 1e-6));
    expect(b.top, lessThan(lastLeaf.top));
  });

  test('los hermanos chicos entre dos grandes quedan repartidos', () {
    TreeLayoutNode big(String id) => TreeLayoutNode(
      id,
      const Size(80, 40),
      children: [
        for (var i = 0; i < 6; i++) TreeLayoutNode('$id$i', const Size(80, 40)),
      ],
    );
    final tree = TreeLayoutNode(
      'r',
      const Size(80, 40),
      children: [
        big('x'),
        const TreeLayoutNode('s1', Size(80, 40)),
        const TreeLayoutNode('s2', Size(80, 40)),
        big('y'),
      ],
    );
    final layout = layoutMindMapTree(tree, gap: 10);
    final x = layout.rects['x']!.center.dy;
    final s1 = layout.rects['s1']!.center.dy;
    final s2 = layout.rects['s2']!.center.dy;
    final y = layout.rects['y']!.center.dy;
    // Con el promedio de los dos apilados, los dos chicos no quedan pegados
    // al primero grande: el espacio de antes y de después es parecido.
    expect((s1 - x - (y - s2)).abs(), lessThan(1e-6));
  });

  test('un solo nodo: el margen alrededor', () {
    final layout = layoutMindMapTree(const TreeLayoutNode('r', Size(120, 44)));
    expect(layout.rects['r'], const Rect.fromLTWH(32, 32, 120, 44));
    expect(layout.size, const Size(184, 108));
    expect(layout.edges, isEmpty);
  });
}
