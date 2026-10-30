import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/domain/services/board_insights.dart';

/// Lo que el Resumen cuenta además del grafo de temas (F44, paso 3): las
/// cifras con su cambio de 30 días, lo nuevo de la semana, para estudiar —con
/// las ramas, como Repasar— y lo suelto. Puro: grafos y hechos armados a mano.
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

  CommunityDetection detection() => CommunityDetection(
    communityOf: Int32List.fromList([1, 0, 0, 0]),
    communities: const [
      TopicCommunity(id: 0, members: [1, 2, 3], anchor: 3, isIsolated: false),
      TopicCommunity(id: 1, members: [0], anchor: 0, isIsolated: true),
    ],
    memory: const CommunityMemory.none(),
    passes: 1,
    converged: true,
    reassigned: 0,
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
    CommunityDetection? communities,
  }) => buildBoardInsights(
    graph: graph(),
    detection: communities ?? detection(),
    facts: BoardFacts(items: items, links: links),
    cards: cards,
    now: now,
  );

  group('las cifras', () {
    test('cuentan todo y lo que sumaron en 30 días, con el borde adentro', () {
      final result = insights(
        [
          item('a', 40, ['roma']),
          item('b', 30, ['grecia']),
          item('c', 30.01, ['grecia']),
          item('d', 2),
        ],
        links: [
          BoardLinkFact(fromId: 'a', toId: 'b', createdAt: daysAgo(3)),
          BoardLinkFact(fromId: 'b', toId: 'c', createdAt: daysAgo(31)),
        ],
      ).figures;

      expect(result.documents, 4);
      // Justo 30 días entra; un poco más, no.
      expect(result.documentsAdded, 2);
      expect(result.links, 2);
      expect(result.linksAdded, 1);
      expect(result.topics, 4);
      expect(result.communities, 1);
    });

    test('un tema es nuevo si su PRIMER documento llegó en estos días', () {
      final result = insights([
        item('a', 40, ['roma']),
        item('b', 2, ['roma']),
        item('c', 5, ['egipto']),
      ]).figures;

      // Roma ya tenía material; Egipto, no; Grecia y República no tienen.
      expect(result.topicsAdded, 1);
    });

    test(
      'una comunidad nace cuando todos sus temas con material son nuevos',
      () {
        final old = insights([
          item('a', 2, ['grecia']),
          item('b', 40, ['roma']),
        ]).figures;
        final born = insights([
          item('a', 2, ['grecia']),
          item('b', 3, ['roma']),
        ]).figures;
        // Una comunidad sin ningún documento directo no nació.
        final empty = insights([item('a', 2)]).figures;

        expect(old.communitiesAdded, 0);
        expect(born.communitiesAdded, 1);
        expect(empty.communitiesAdded, 0);
      },
    );
  });

  group('lo nuevo de la semana', () {
    test('lo de los últimos 7 días, lo último primero, con su tema con más '
        'material', () {
      final result = insights([
        item('viejo', 8, ['roma']),
        item('a', 1, ['egipto', 'roma', 'grecia']),
        item('b', 3),
        item('c', 6.9, ['republica']),
      ]);

      expect([for (final i in result.newItems) i.id], ['a', 'b', 'c']);
      expect(result.newItemCount, 3);
      // Grecia y Roma tienen dos; a igual material, la primera por nombre.
      expect(result.newItems.first.topic?.valueId, 'grecia');
      expect(result.newItems[1].topic, isNull);
    });

    test('corta en cinco pero cuenta todos', () {
      final result = insights([
        for (var i = 0; i < 8; i++) item('d$i', i * 0.5),
      ]);

      expect(result.newItems, hasLength(kBoardNewRows));
      expect(result.newItemCount, 8);
      expect(result.newItems.first.id, 'd0');
    });

    test('los vínculos de la semana, con sus títulos', () {
      final result = insights(
        [item('a', 20), item('b', 20)],
        links: [
          BoardLinkFact(fromId: 'a', toId: 'b', createdAt: daysAgo(1)),
          BoardLinkFact(fromId: 'b', toId: 'a', createdAt: daysAgo(9)),
        ],
      );

      expect(result.newLinkCount, 1);
      expect(result.newLinks.single.fromTitle, 'Título a');
      expect(result.newLinks.single.toTitle, 'Título b');
    });
  });

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
        detection: CommunityDetection.empty(const CommunityMemory.none()),
        facts: BoardFacts(
          items: [
            for (var i = 0; i < 9; i++) item('i$i', 50, ['t$i']),
          ],
          links: const [],
        ),
        cards: const {},
        now: now,
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
