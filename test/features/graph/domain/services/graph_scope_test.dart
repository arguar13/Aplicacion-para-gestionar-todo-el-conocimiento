import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/graph/domain/services/graph_scope.dart';

void main() {
  KnowledgeItem item(String id) {
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
}
