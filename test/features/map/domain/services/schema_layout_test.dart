import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/services/schema_layout.dart';

/// Los layouts del esquema (F14, D6): radial y de árbol, sobre un árbol que ya
/// viene armado y recortado.
void main() {
  SchemaNode leaf(String id) => SchemaNode(id);

  SchemaNode node(String id, List<SchemaNode> children) =>
      SchemaNode(id, children: children);

  /// Cuántos grados (0–360) hay desde el eje horizontal hasta el nodo.
  double angleOf(Offset p) {
    final degrees = math.atan2(p.dy, p.dx) * 180 / math.pi;
    return degrees < 0 ? degrees + 360 : degrees;
  }

  /// A: tres hojas; B: una hoja. A pesa el triple que B.
  SchemaNode unbalanced() => node('raiz', [
    node('a', [leaf('a1'), leaf('a2'), leaf('a3')]),
    leaf('b'),
  ]);

  group('el esquema radial', () {
    test('la raíz sola va al origen', () {
      final layout = layoutRadial(leaf('raiz'));

      expect(layout.positions, {'raiz': Offset.zero});
    });

    test('los hijos de la raíz se reparten en un anillo, a igual distancia y '
        'a igual ángulo', () {
      final layout = layoutRadial(
        node('raiz', [for (var i = 0; i < 4; i++) leaf('h$i')]),
      );

      expect(layout.positions['raiz'], Offset.zero);
      final angles = <double>[];
      for (var i = 0; i < 4; i++) {
        final p = layout.positions['h$i']!;
        expect(p.distance, closeTo(140, 1e-9));
        angles.add(angleOf(p));
      }
      angles.sort();
      for (var i = 1; i < 4; i++) {
        expect(angles[i] - angles[i - 1], closeTo(90, 1e-6));
      }
    });

    test('cada rama se lleva un sector proporcional a sus hojas, y sus hijos '
        'cuelgan de él', () {
      final layout = layoutRadial(unbalanced());

      // Cuatro hojas: A se lleva tres cuartos del círculo (0°–270°) y B el
      // resto (270°–360°).
      expect(angleOf(layout.positions['a']!), closeTo(135, 1e-6));
      expect(angleOf(layout.positions['b']!), closeTo(315, 1e-6));
      for (final (id, expected) in [
        ('a1', 45.0),
        ('a2', 135.0),
        ('a3', 225.0),
      ]) {
        expect(angleOf(layout.positions[id]!), closeTo(expected, 1e-6));
      }
    });

    test('cada nivel está en un anillo más afuera que el anterior', () {
      final layout = layoutRadial(unbalanced(), ringGap: 100);

      final root = layout.positions['raiz']!.distance;
      final middle = layout.positions['a']!.distance;
      final outer = layout.positions['a1']!.distance;
      expect(root, 0);
      expect(middle, greaterThanOrEqualTo(100 - 1e-9));
      expect(outer, greaterThanOrEqualTo(middle + 100 - 1e-9));
    });

    test('un anillo muy poblado se ensancha para que los nodos no se '
        'encimen', () {
      final layout = layoutRadial(
        node('raiz', [for (var i = 0; i < 60; i++) leaf('h$i')]),
        ringGap: 100,
      );

      final ring = [for (var i = 0; i < 60; i++) layout.positions['h$i']!];
      // 60 nodos a 56 de distancia piden más de 534 de radio, y no los 100 de
      // un anillo común.
      expect(ring.first.distance, greaterThan(500));
      var closest = double.infinity;
      for (var i = 0; i < ring.length; i++) {
        for (var j = i + 1; j < ring.length; j++) {
          closest = math.min(closest, (ring[i] - ring[j]).distance);
        }
      }
      expect(closest, greaterThanOrEqualTo(56 * 0.99));
    });

    test('una cadena larga sigue hacia afuera sin cruzarse', () {
      final chain = node('a', [
        node('b', [
          node('c', [
            node('d', [leaf('e')]),
          ]),
        ]),
      ]);

      final layout = layoutRadial(chain, ringGap: 80);

      final distances = [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          layout.positions[id]!.distance,
      ];
      for (var i = 1; i < distances.length; i++) {
        expect(distances[i], closeTo(distances[i - 1] + 80, 1e-6));
      }
    });

    test('el mismo árbol da siempre el mismo layout', () {
      final a = layoutRadial(unbalanced());
      final b = layoutRadial(unbalanced());

      expect(b.positions, a.positions);
    });
  });

  group('el esquema como árbol', () {
    test(
      'cada padre queda centrado sobre sus hijos, y las hojas separadas',
      () {
        final layout = layoutTree(unbalanced(), levelGap: 100, siblingGap: 60);
        final p = layout.positions;

        // Hojas: a1, a2, a3, b en las posiciones 0, 60, 120, 180.
        expect(p['a1']!.dx, 0);
        expect(p['a2']!.dx, 60);
        expect(p['a3']!.dx, 120);
        expect(p['b']!.dx, 180);
        // A, sobre a1..a3; la raíz, entre A y B.
        expect(p['a']!.dx, 60);
        expect(p['raiz']!.dx, (60 + 180) / 2);
        // Un nivel cada 100.
        expect(p['raiz']!.dy, 0);
        expect(p['a']!.dy, 100);
        expect(p['a1']!.dy, 200);
        expect(p['b']!.dy, 100);
      },
    );

    test('hacia la derecha, los niveles avanzan en x', () {
      final layout = layoutTree(
        unbalanced(),
        levelGap: 100,
        siblingGap: 60,
        direction: SchemaDirection.right,
      );
      final p = layout.positions;

      expect(p['raiz']!.dx, 0);
      expect(p['a']!.dx, 100);
      expect(p['a1']!.dx, 200);
      expect(p['a2']!.dy, 60);
    });

    test('dos nodos del mismo nivel nunca quedan más cerca que el espacio '
        'entre hermanos', () {
      // Un árbol desparejo: ramas de distinta profundidad.
      final tree = node('raiz', [
        node('a', [
          node('a1', [leaf('a11'), leaf('a12')]),
          leaf('a2'),
        ]),
        node('b', [leaf('b1')]),
        node('c', [
          node('c1', [leaf('c11')]),
        ]),
        leaf('d'),
      ]);

      final layout = layoutTree(tree, levelGap: 100);

      final byLevel = <double, List<double>>{};
      for (final p in layout.positions.values) {
        byLevel.putIfAbsent(p.dy, () => []).add(p.dx);
      }
      for (final xs in byLevel.values) {
        xs.sort();
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i] - xs[i - 1], greaterThanOrEqualTo(64 - 1e-9));
        }
      }
    });

    test('la raíz sola va al origen', () {
      expect(layoutTree(leaf('raiz')).positions, {'raiz': Offset.zero});
    });
  });

  group('los dos', () {
    test('un identificador repetido se dibuja una sola vez', () {
      final tree = node('raiz', [
        node('a', [leaf('x')]),
        node('b', [leaf('x')]),
      ]);

      for (final layout in [layoutRadial(tree), layoutTree(tree)]) {
        expect(layout.positions.keys.toSet(), {'raiz', 'a', 'b', 'x'});
      }
      expect(schemaSize(tree), 4);
    });

    test('un ciclo no cuelga el dibujo', () {
      final aChildren = <SchemaNode>[];
      final a = SchemaNode('a', children: aChildren);
      final b = SchemaNode('b', children: [a]);
      aChildren.add(b);

      expect(layoutRadial(a).positions.keys.toSet(), {'a', 'b'});
      expect(layoutTree(a).positions.keys.toSet(), {'a', 'b'});
    });

    test('los límites abarcan los centros de todos los nodos', () {
      final layout = layoutTree(unbalanced(), levelGap: 100, siblingGap: 60);

      expect(layout.bounds, const Rect.fromLTRB(0, 0, 180, 200));
      expect(const SchemaLayout({}).bounds, Rect.zero);
    });
  });
}
