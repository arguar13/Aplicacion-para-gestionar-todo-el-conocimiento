import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';

/// Lo que se dibuja en cada nivel del grafo de conocimiento (F14), sin
/// posiciones: qué nodos, con qué tamaño y color, unidos por qué.
void main() {
  /// a, b (comunidad 5); c, d (comunidad 6); e aislado (comunidad 7).
  TopicGraph graph() => TopicGraph(
    definitionId: 'tema',
    definitionName: 'Tema',
    nodes: [
      for (final (id, items) in [
        ('a', 4),
        ('b', 2),
        ('c', 3),
        ('d', 1),
        ('e', 5),
      ])
        TopicNode(valueId: id, label: 'Tema $id', depth: 0, itemCount: items),
    ],
    edges: [
      const TopicEdge(
        a: 0,
        b: 1,
        cooccurrence: 3,
        relations: 0,
        contradictions: 0,
        openContradictions: 0,
      ),
      const TopicEdge(
        a: 2,
        b: 3,
        cooccurrence: 2,
        relations: 0,
        contradictions: 0,
        openContradictions: 0,
      ),
      const TopicEdge(
        a: 1,
        b: 2,
        cooccurrence: 0,
        relations: 0,
        contradictions: 1,
        openContradictions: 1,
      ),
    ],
  );

  CommunityDetection detection() => CommunityDetection(
    communityOf: Int32List.fromList([5, 5, 6, 6, 7]),
    communities: const [
      TopicCommunity(id: 5, members: [0, 1], anchor: 0, isIsolated: false),
      TopicCommunity(id: 6, members: [2, 3], anchor: 2, isIsolated: false),
      TopicCommunity(id: 7, members: [4], anchor: 4, isIsolated: true),
    ],
    memory: const CommunityMemory.none(),
    passes: 1,
    converged: true,
    reassigned: 0,
  );

  test('el panorama: un nodo por comunidad, con su nombre, su tamaño y su '
      'color', () {
    final g = graph();
    final scene = sceneOfOverview(g, aggregateCommunities(g, detection()));

    expect(scene.nodes.map((n) => n.kind), [
      SceneKind.community,
      SceneKind.community,
      SceneKind.isolated,
    ]);
    final first = scene.nodes.first;
    expect(first.label, 'Tema a');
    expect(first.size, 6);
    expect(first.count, 2);
    expect(first.group, 5);
    // Los aislados no tienen comunidad a la que colorear, ni nombre propio.
    expect(scene.nodes.last.group, isNull);
    expect(scene.nodes.last.label, '');
    expect(scene.nodes.map((n) => n.key).toSet(), hasLength(3));
  });

  test('el panorama: la unión entre dos comunidades es una tensión si alguna '
      'de sus uniones lo es', () {
    final g = graph();
    final scene = sceneOfOverview(g, aggregateCommunities(g, detection()));

    final edge = scene.edges.single;
    expect((edge.a, edge.b), (0, 1));
    expect(edge.tension, isTrue);
    expect(edge.weight, 3);
  });

  test('los temas: coloreados por su comunidad, con las uniones dentro de la '
      'selección', () {
    final g = graph();
    final selection = selectTopics(g, focus: {0}, limit: 3);

    final scene = sceneOfTopics(g, detection(), selection);

    // El foco, su vecino más unido y el vecino del vecino.
    expect(scene.nodes.map((n) => n.ref), ['a', 'b', 'c']);
    expect(scene.nodes.map((n) => n.group), [5, 5, 6]);
    expect(scene.nodes.first.kind, SceneKind.topic);
    expect(scene.nodes.first.key, 'topic:a');
    expect(scene.edges.length, 2);
    expect(scene.hidden, 2);
    // La unión b–c es la contradicción.
    final tension = scene.edges.singleWhere((e) => e.tension);
    expect(scene.nodes[tension.a].ref, 'b');
    expect(scene.nodes[tension.b].ref, 'c');
  });

  group('el tope de uniones del nivel de temas', () {
    /// Todos con todos entre [n] nodos, con pesos que se repiten pero no
    /// siempre.
    List<SceneEdge> everyPair(int n) => [
      for (var a = 0; a < n; a++)
        for (var b = a + 1; b < n; b++)
          SceneEdge(a: a, b: b, weight: 1.0 + (a * 7 + b * 3) % 11),
    ];

    test('cada nodo conserva las más fuertes de las suyas', () {
      final edges = everyPair(8);

      final kept = strongestEdges(edges, 8, perNode: 2);

      expect(kept.length, lessThan(edges.length));
      for (var node = 0; node < 8; node++) {
        // Las dos más fuertes de este nodo, con el orden de siempre: por peso
        // y, a igual peso, la que venía antes.
        final incident =
            [
              for (var i = 0; i < edges.length; i++)
                if (edges[i].a == node || edges[i].b == node) i,
            ]..sort((x, y) {
              final byWeight = edges[y].weight.compareTo(edges[x].weight);
              return byWeight != 0 ? byWeight : x.compareTo(y);
            });
        for (final i in incident.take(2)) {
          expect(kept, contains(edges[i]), reason: 'nodo $node, unión $i');
        }
      }
    });

    test('no pasa de perNode por nodo', () {
      final edges = everyPair(40);

      final kept = strongestEdges(edges, 40);

      expect(kept.length, lessThanOrEqualTo(40 * kTopicEdgesPerNode));
      expect(kept.length, lessThan(edges.length ~/ 4));
    });

    test('las contradicciones se conservan siempre, aunque sean débiles', () {
      final edges = [
        ...everyPair(6),
        const SceneEdge(a: 0, b: 1, weight: 0.1, tension: true),
      ];

      final kept = strongestEdges(edges, 6, perNode: 1);

      expect(kept.where((e) => e.tension), hasLength(1));
    });

    test('es determinista y conserva el orden en que venían', () {
      final edges = [
        for (var i = 1; i <= 6; i++) SceneEdge(a: 0, b: i, weight: 2),
        for (var i = 1; i <= 6; i++) SceneEdge(a: i, b: i % 6 + 1, weight: 2),
      ];

      final first = strongestEdges(edges, 7, perNode: 2);
      final second = strongestEdges(edges, 7, perNode: 2);

      expect(first, second);
      final positions = [for (final e in first) edges.indexOf(e)];
      expect(positions, [...positions]..sort());
    });

    test('con pocas uniones por nodo no toca ninguna', () {
      final edges = [
        for (var i = 1; i <= 3; i++) SceneEdge(a: 0, b: i, weight: i * 1.0),
      ];

      expect(strongestEdges(edges, 4), edges);
    });

    test('la escena de temas dibuja las más fuertes y dice cuántas dejó', () {
      // Doce temas que aparecen todos juntos: todos con todos.
      final g = TopicGraph(
        definitionId: 'tema',
        definitionName: 'Tema',
        nodes: [
          for (var i = 0; i < 12; i++)
            TopicNode(valueId: 't$i', label: 'T$i', depth: 0, itemCount: 3),
        ],
        edges: [
          for (var a = 0; a < 12; a++)
            for (var b = a + 1; b < 12; b++)
              TopicEdge(
                a: a,
                b: b,
                cooccurrence: 1 + (a + b) % 5,
                relations: 0,
                contradictions: 0,
                openContradictions: 0,
              ),
        ],
      );
      final together = CommunityDetection(
        communityOf: Int32List(12),
        communities: const [
          TopicCommunity(
            id: 0,
            members: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
            anchor: 0,
            isIsolated: false,
          ),
        ],
        memory: const CommunityMemory.none(),
        passes: 1,
        converged: true,
        reassigned: 0,
      );

      final scene = sceneOfTopics(g, together, selectTopics(g));

      // 66 uniones posibles, y a lo sumo cuatro por tema.
      expect(scene.edges.length + scene.hiddenEdges, 66);
      expect(scene.edges.length, lessThanOrEqualTo(12 * kTopicEdgesPerNode));
      expect(scene.hiddenEdges, greaterThan(0));
    });

    test('con pocas uniones, la escena no dice que dejó ninguna', () {
      final g = graph();

      final scene = sceneOfTopics(g, detection(), selectTopics(g));

      expect(scene.hiddenEdges, 0);
    });
  });

  test('los temas: un subtema se une a su padre con la jerarquía, y suma a lo '
      'que ya los une', () {
    final g = TopicGraph(
      definitionId: 'tema',
      definitionName: 'Tema',
      nodes: const [
        TopicNode(valueId: 'padre', label: 'Padre', depth: 0, itemCount: 3),
        TopicNode(
          valueId: 'hijo',
          label: 'Hijo',
          parentId: 'padre',
          depth: 1,
          itemCount: 1,
        ),
        TopicNode(
          valueId: 'nieto',
          label: 'Nieto',
          parentId: 'hijo',
          depth: 2,
          itemCount: 1,
        ),
        TopicNode(valueId: 'otro', label: 'Otro', depth: 0, itemCount: 1),
      ],
      edges: const [
        // Padre e hijo ya comparten un elemento.
        TopicEdge(
          a: 0,
          b: 1,
          cooccurrence: 2,
          relations: 0,
          contradictions: 0,
          openContradictions: 0,
        ),
      ],
    );
    final selection = selectTopics(g, limit: 10);

    final scene = sceneOfTopics(g, detectCommunities(g), selection);

    // Padre–hijo: 2 de coocurrencia + 1 de jerarquía, en una sola unión.
    // Hijo–nieto: solo la jerarquía. Otro no tiene ninguna.
    expect(scene.edges, hasLength(2));
    final byPair = {
      for (final e in scene.edges)
        (scene.nodes[e.a].ref, scene.nodes[e.b].ref): e.weight,
    };
    expect(byPair[('padre', 'hijo')], 3);
    expect(byPair[('hijo', 'nieto')], 1);
  });

  test('los elementos: notas y fuentes, y cada vínculo con su tipo', () {
    const items = TopicItemsGraph(
      valueId: 'a',
      items: [
        TopicItemNode(id: 'n1', title: 'Nota', isNote: true),
        TopicItemNode(id: 's1', title: 'Fuente', isNote: false),
        TopicItemNode(id: 's2', title: 'Otra', isNote: false),
      ],
      edges: [
        TopicItemEdge(a: 0, b: 1, kind: RelationKind.cites),
        TopicItemEdge(a: 1, b: 2, kind: RelationKind.contradicts),
      ],
      truncated: true,
    );

    final scene = sceneOfItems(items);

    expect(scene.nodes.map((n) => n.kind), [
      SceneKind.note,
      SceneKind.source,
      SceneKind.source,
    ]);
    expect(scene.nodes.first.key, 'item:n1');
    expect(scene.nodes.first.ref, 'n1');
    expect(scene.edges.first.relation, RelationKind.cites);
    expect(scene.edges.first.tension, isFalse);
    expect(scene.edges.last.tension, isTrue);
    expect(scene.edges.last.weight, greaterThan(scene.edges.first.weight));
    expect(scene.hidden, 1);
  });

  test('las uniones se dan al layout con su peso', () {
    final g = graph();
    final scene = sceneOfOverview(g, aggregateCommunities(g, detection()));

    final links = scene.links;

    expect(links, hasLength(1));
    expect(links.single.weight, 3);
  });

  test('una escena vacía no tiene nada, y busca un nodo por su clave', () {
    expect(const GraphScene.empty().nodes, isEmpty);
    final g = graph();
    final scene = sceneOfTopics(g, detection(), selectTopics(g, limit: 10));

    expect(scene.indexOf('topic:c'), 2);
    expect(scene.indexOf('topic:zzz'), isNull);
  });
}
