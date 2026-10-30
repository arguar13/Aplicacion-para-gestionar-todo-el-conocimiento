import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/domain/services/board_insights.dart';

/// Lo que el Resumen cuenta por su cuenta (F44, paso 3): para estudiar —con las
/// ramas, como Repasar— y lo suelto. Las cifras, lo nuevo y los puentes los
/// entrega el motor del Mapa (`MapInsights`) y se prueban con él. Puro: un
/// grafo y unos hechos armados a mano.
void main() {
  final now = DateTime(2026, 10, 30, 12);
  DateTime daysAgo(num days) =>
      now.subtract(Duration(minutes: (days * 24 * 60).round()));

  /// roma ─ república (su rama), grecia y egipto. Roma y Grecia, una
  /// comunidad; Egipto, aislado.
  TopicGraph graph() => TopicGraph(
    definitionId: 'tema',
    definitionName: 'Tema',
    nodes: const [
      TopicNode(valueId: 'egipto', label: 'Egipto', depth: 0, itemCount: 1),
      TopicNode(valueId: 'grecia', label: 'Grecia', depth: 0, itemCount: 2),
      TopicNode(
        valueId: 'republica',
        label: 'República',
        depth: 1,
        itemCount: 1,
        parentId: 'roma',
      ),
      TopicNode(valueId: 'roma', label: 'Roma', depth: 0, itemCount: 2),
    ],
    edges: const [
      TopicEdge(
        a: 1,
        b: 3,
        cooccurrence: 1,
        relations: 0,
        contradictions: 0,
        openContradictions: 0,
      ),
      TopicEdge(
        a: 2,
        b: 3,
        cooccurrence: 1,
        relations: 0,
        contradictions: 0,
        openContradictions: 0,
      ),
    ],
  );

  BoardItemFact item(String id, num days, [List<String> values = const []]) =>
      BoardItemFact(
        id: id,
        title: 'Título $id',
        createdAt: daysAgo(days),
        valueIds: values,
      );

  BoardInsights insights(
    List<BoardItemFact> items, {
    List<BoardLinkFact> links = const [],
    Map<String, BoardCardFact> cards = const {},
  }) => buildBoardInsights(
    graph: graph(),
    facts: BoardFacts(items: items, links: links),
    cards: cards,
  );

  group('para estudiar', () {
    test('un subtema suma a su padre, y un documento en los dos cuenta UNA '
        'vez', () {
      final result = insights(
        [
          item('a', 50, ['republica', 'roma']),
          item('b', 50, ['roma']),
          item('c', 50, ['grecia']),
        ],
        cards: const {
          'a': BoardCardFact(cards: 3, dueToday: 2),
          'b': BoardCardFact(cards: 1, dueToday: 1),
        },
      );

      final roma = result.dueTopics.firstWhere(
        (t) => t.topic.valueId == 'roma',
      );
      expect(roma.documents, 2);
      expect(roma.cards, 4);
      expect(roma.dueToday, 3);
      final republica = result.dueTopics.firstWhere(
        (t) => t.topic.valueId == 'republica',
      );
      expect(republica.dueToday, 2);
      // Las de más tarjetas para hoy primero.
      expect(
        [for (final t in result.dueTopics) t.topic.valueId],
        ['roma', 'republica'],
      );
      // Grecia tiene material y ninguna tarjeta.
      expect(
        [for (final t in result.uncardedTopics) t.topic.valueId],
        ['grecia'],
      );
    });

    test('lo que está solo en un subtema llega a su padre: Roma estudia lo '
        'de la República', () {
      final result = insights(
        [
          item('a', 50, ['republica']),
        ],
        cards: const {'a': BoardCardFact(cards: 2, dueToday: 1)},
      );

      expect(
        [for (final t in result.dueTopics) (t.topic.valueId, t.documents)],
        [('republica', 1), ('roma', 1)],
      );
    });

    test('con tarjetas que no tocan hoy, el tema no está en ninguna lista', () {
      final result = insights(
        [
          item('a', 50, ['egipto']),
        ],
        cards: const {'a': BoardCardFact(cards: 2, dueToday: 0)},
      );

      expect(result.dueTopics, isEmpty);
      expect(result.uncardedTopics, isEmpty);
    });

    test('sin tarjetas, los de más material primero; a igual material, por '
        'nombre', () {
      final result = insights([
        item('a', 50, ['egipto']),
        item('b', 50, ['grecia']),
        item('c', 50, ['grecia']),
        item('d', 50, ['roma']),
      ]);

      expect(
        [for (final t in result.uncardedTopics) t.topic.valueId],
        ['grecia', 'egipto', 'roma'],
      );
    });

    test('corta en cinco', () {
      final many = TopicGraph(
        definitionId: 'tema',
        definitionName: 'Tema',
        nodes: [
          for (var i = 0; i < 9; i++)
            TopicNode(valueId: 't$i', label: 'T$i', depth: 0, itemCount: 1),
        ],
        edges: const [],
      );
      final result = buildBoardInsights(
        graph: many,
        facts: BoardFacts(
          items: [
            for (var i = 0; i < 9; i++) item('i$i', 50, ['t$i']),
          ],
          links: const [],
        ),
        cards: const {},
      );

      expect(result.uncardedTopics, hasLength(kBoardStudyRows));
    });
  });

  test('lo suelto: los documentos sin ningún vínculo, lo último primero', () {
    final result = insights(
      [
        for (var i = 0; i < 9; i++) item('s$i', 10 - i),
        item('x', 1),
        item('y', 1),
      ],
      links: [BoardLinkFact(fromId: 'x', toId: 'y', createdAt: daysAgo(1))],
    );

    expect(result.looseItemIds, [for (var i = 8; i >= 0; i--) 's$i']);
    expect(result.looseItems, hasLength(kBoardLooseRows));
    expect(result.looseItems.first.id, 's8');
  });
}
