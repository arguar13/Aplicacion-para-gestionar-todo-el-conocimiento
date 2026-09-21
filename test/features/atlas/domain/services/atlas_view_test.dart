import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_view.dart';

/// Qué ramas del Atlas se ven: el árbol plegado, el desplegado y la búsqueda.
void main() {
  AtlasNode node(
    String id,
    String label,
    int depth, {
    String? parent,
    int children = 0,
  }) => AtlasNode(
    valueId: id,
    label: label,
    depth: depth,
    parentId: parent,
    childCount: children,
  );

  /// Roma ─ República ─ Gracos, Roma ─ Imperio, y Grecia sola. En preorden.
  final snapshot = AtlasSnapshot(
    definitionId: 'tema',
    definitionName: 'Tema',
    nodes: [
      node('grecia', 'Grecia', 0),
      node('roma', 'Roma', 0, children: 2),
      node('imperio', 'Imperio', 1, parent: 'roma'),
      node('republica', 'República', 1, parent: 'roma', children: 1),
      node('gracos', 'Gracos', 2, parent: 'republica'),
    ],
    gaps: const [],
  );

  List<String> ids(Set<String> expanded, {String query = ''}) => [
    for (final n in visibleAtlasNodes(
      snapshot,
      expanded: expanded,
      query: query,
    ))
      n.valueId,
  ];

  group('sin búsqueda', () {
    test('plegado: solo las raíces', () {
      expect(ids({}), ['grecia', 'roma']);
    });

    test('desplegar una rama muestra sus hijos, plegados', () {
      expect(ids({'roma'}), ['grecia', 'roma', 'imperio', 'republica']);
    });

    test('desplegar todo lo que tiene hijos muestra el árbol entero', () {
      expect(ids({'roma', 'republica'}), [
        'grecia',
        'roma',
        'imperio',
        'republica',
        'gracos',
      ]);
    });

    test('un nieto desplegado bajo un abuelo plegado no se ve', () {
      expect(ids({'republica'}), ['grecia', 'roma']);
    });

    test('plegar el abuelo oculta también lo que el nieto tenía abierto', () {
      // República sigue «abierta», pero Roma no: Gracos no se ve.
      expect(ids({'republica'}), isNot(contains('gracos')));
      expect(ids({'roma', 'republica'}), contains('gracos'));
    });

    test('un valor sin hijos que figura como desplegado no cambia nada', () {
      expect(ids({'grecia'}), ['grecia', 'roma']);
    });
  });

  group('con búsqueda', () {
    test('encuentra el tema donde esté, aunque su rama esté plegada', () {
      expect(ids({}, query: 'gracos'), ['roma', 'republica', 'gracos']);
    });

    test('conserva los ascendientes de lo que encuentra, sin sus hermanos', () {
      final found = ids({}, query: 'imperio');

      expect(found, ['roma', 'imperio']);
      expect(found, isNot(contains('republica')));
    });

    test('no distingue mayúsculas ni acentos', () {
      expect(ids({}, query: 'REPUBLICA'), ['roma', 'republica']);
      expect(ids({}, query: 'república'), ['roma', 'republica']);
    });

    test(
      'varias coincidencias comparten el camino, cada ascendiente una vez',
      () {
        // La «r» está en todos los nombres: cada uno entra, y Roma y República
        // —que también son ascendientes— una sola vez.
        expect(ids({}, query: 'r'), [
          'grecia',
          'roma',
          'imperio',
          'republica',
          'gracos',
        ]);
      },
    );

    test('sin coincidencias, nada', () {
      expect(ids({}, query: 'egipto'), isEmpty);
    });

    test('una búsqueda en blanco es como no buscar', () {
      expect(ids({}, query: '   '), ['grecia', 'roma']);
    });
  });
}
