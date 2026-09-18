import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';

void main() {
  KnowledgeItem item(String id, {String? spaceId}) {
    return KnowledgeItem(
      id: id,
      title: id,
      source: Source(
        id: '$id-src',
        kind: SourceKind.manualNote,
        capturedAt: DateTime(2026),
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      spaceId: spaceId,
    );
  }

  RelationEdge edge(String id, String from, String to) {
    return RelationEdge(
      id: id,
      fromItemId: from,
      toItemId: to,
      kind: RelationKind.relatedTo,
    );
  }

  group('sin espacio elegido', () {
    test('devuelve todos los vínculos tal cual, sin recortar nada', () {
      final items = [item('a'), item('b'), item('c')];
      final edges = [edge('e1', 'a', 'b'), edge('e2', 'b', 'c')];

      final result = scopeGraph(items: items, edges: edges, spaceId: null);

      expect(result.nodeIds.toSet(), {'a', 'b', 'c'});
      expect(result.edges, edges);
    });

    test('descarta un vínculo que apunta a un elemento que ya no existe', () {
      final items = [item('a')];
      final edges = [edge('e1', 'a', 'perdido')];

      final result = scopeGraph(items: items, edges: edges, spaceId: null);

      expect(result.edges, isEmpty);
      expect(result.nodeIds, isEmpty);
    });
  });

  group('con un espacio elegido', () {
    test('grado 0 muestra solo lo que conecta puertas adentro del espacio', () {
      final items = [
        item('a', spaceId: 'sp1'),
        item('b', spaceId: 'sp1'),
        item('c', spaceId: 'sp2'),
      ];
      final edges = [
        edge('e1', 'a', 'b'), // dentro del espacio
        edge('e2', 'b', 'c'), // sale del espacio
      ];

      final result = scopeGraph(
        items: items,
        edges: edges,
        spaceId: 'sp1',
        degree: 0,
      );

      expect(result.nodeIds.toSet(), {'a', 'b'});
      expect(result.edges, [edges.first]);
    });

    test('grado 1 suma un salto más allá del espacio', () {
      final items = [
        item('a', spaceId: 'sp1'),
        item('b', spaceId: 'sp1'),
        item('c', spaceId: 'sp2'),
        item('d', spaceId: 'sp2'),
      ];
      final edges = [
        edge('e1', 'a', 'b'),
        edge('e2', 'b', 'c'),
        edge('e3', 'c', 'd'), // dos saltos desde el espacio: no debería entrar
      ];

      final result = scopeGraph(
        items: items,
        edges: edges,
        spaceId: 'sp1',
        degree: 1,
      );

      expect(result.nodeIds.toSet(), {'a', 'b', 'c'});
      expect(result.edges.map((e) => e.id).toSet(), {'e1', 'e2'});
    });

    test('grado nulo expande sin techo, hasta el borde de la red', () {
      final items = [
        item('a', spaceId: 'sp1'),
        item('b', spaceId: 'sp2'),
        item('c', spaceId: 'sp2'),
        item('d', spaceId: 'sp3'),
      ];
      final edges = [
        edge('e1', 'a', 'b'),
        edge('e2', 'b', 'c'),
        edge('e3', 'c', 'd'),
      ];

      final result = scopeGraph(items: items, edges: edges, spaceId: 'sp1');

      expect(result.nodeIds.toSet(), {'a', 'b', 'c', 'd'});
      expect(result.edges.length, 3);
    });

    test('un espacio sin ningún vínculo no muestra nada', () {
      final items = [item('a', spaceId: 'sp1'), item('b', spaceId: 'sp2')];
      final edges = [edge('e1', 'a', 'b')];

      final result = scopeGraph(
        items: items,
        edges: edges,
        spaceId: 'sp-vacio',
      );

      expect(result.nodeIds, isEmpty);
      expect(result.edges, isEmpty);
    });
  });

  group('localGraphFrom', () {
    test('una semilla sin ningún vínculo devuelve un resultado vacío', () {
      final items = [item('a'), item('b')];

      final result = localGraphFrom(seedItemId: 'a', items: items, edges: []);

      expect(result.nodeIds, isEmpty);
      expect(result.edges, isEmpty);
    });

    test('un salto trae al vecino directo', () {
      final items = [item('a'), item('b'), item('c')];
      final edges = [edge('e1', 'a', 'b'), edge('e2', 'b', 'c')];

      final result = localGraphFrom(
        seedItemId: 'a',
        items: items,
        edges: edges,
      );

      expect(result.nodeIds.toSet(), {'a', 'b'});
      expect(result.edges.map((e) => e.id).toSet(), {'e1'});
    });

    test('degree: 2 suma un salto más', () {
      final items = [item('a'), item('b'), item('c'), item('d')];
      final edges = [
        edge('e1', 'a', 'b'),
        edge('e2', 'b', 'c'),
        edge('e3', 'c', 'd'), // tres saltos desde 'a': no debería entrar
      ];

      final result = localGraphFrom(
        seedItemId: 'a',
        items: items,
        edges: edges,
        degree: 2,
      );

      expect(result.nodeIds.toSet(), {'a', 'b', 'c'});
      expect(result.edges.map((e) => e.id).toSet(), {'e1', 'e2'});
    });

    test('degree: null expande sin techo, hasta el borde de la red', () {
      final items = [item('a'), item('b'), item('c'), item('d')];
      final edges = [
        edge('e1', 'a', 'b'),
        edge('e2', 'b', 'c'),
        edge('e3', 'c', 'd'),
      ];

      final result = localGraphFrom(
        seedItemId: 'a',
        items: items,
        edges: edges,
        degree: null,
      );

      expect(result.nodeIds.toSet(), {'a', 'b', 'c', 'd'});
      expect(result.edges, hasLength(3));
    });

    test('una semilla que no existe entre los items no revienta', () {
      final items = [item('a'), item('b')];
      final edges = [edge('e1', 'a', 'b')];

      final result = localGraphFrom(
        seedItemId: 'no-existe',
        items: items,
        edges: edges,
      );

      expect(result.nodeIds, isEmpty);
      expect(result.edges, isEmpty);
    });

    test('el default de degree es 1, no sin techo', () {
      final items = [item('a'), item('b'), item('c')];
      final edges = [edge('e1', 'a', 'b'), edge('e2', 'b', 'c')];

      final result = localGraphFrom(
        seedItemId: 'a',
        items: items,
        edges: edges,
      );

      expect(result.nodeIds.toSet(), {'a', 'b'});
    });
  });

  group('computeConnectedComponents', () {
    test('sin nodos, no hay componentes', () {
      final result = computeConnectedComponents(nodeIds: [], edges: []);

      expect(result, isEmpty);
    });

    test('todo vinculado en cadena queda en un solo componente', () {
      final result = computeConnectedComponents(
        nodeIds: ['a', 'b', 'c'],
        edges: [edge('e1', 'a', 'b'), edge('e2', 'b', 'c')],
      );

      expect(result, [
        {'a', 'b', 'c'},
      ]);
    });

    test('dos grupos sin ningún vínculo entre ellos quedan separados', () {
      // Es justamente lo que arma "un grafo por tema": nada conecta 'a' con
      // 'c', así que son dos temas distintos, no uno con cuatro elementos.
      final result = computeConnectedComponents(
        nodeIds: ['a', 'b', 'c', 'd'],
        edges: [edge('e1', 'a', 'b'), edge('e2', 'c', 'd')],
      );

      // `expect` compara colecciones anidadas por contenido, no por
      // identidad — a diferencia del matcher `contains`, que llama al
      // `.contains()` de la propia lista y ahí sí compara por `==`, que un
      // `Set` no redefine. Por eso se compara la lista entera de una, en
      // vez de buscar cada componente por separado.
      expect(result, [
        {'a', 'b'},
        {'c', 'd'},
      ]);
    });

    test('el componente más grande va primero', () {
      final result = computeConnectedComponents(
        nodeIds: ['a', 'b', 'c', 'd', 'e'],
        edges: [
          edge('e1', 'a', 'b'), // componente chico: 2
          edge('e2', 'c', 'd'),
          edge('e3', 'd', 'e'), // componente grande: 3
        ],
      );

      expect(result.first, {'c', 'd', 'e'});
      expect(result.last, {'a', 'b'});
    });

    test('un nodo sin ningún vínculo es su propio componente', () {
      // No pasa en la práctica —`scopeGraph` solo arma `nodeIds` a partir de
      // aristas, así que un nodo suelto nunca llega hasta acá—, pero la
      // función no debería reventar si algún día lo hace.
      final result = computeConnectedComponents(nodeIds: ['solo'], edges: []);

      expect(result, [
        {'solo'},
      ]);
    });
  });
}
