import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';

/// Los niveles de detalle del mapa (F14, D5): de lejos, comunidades; a
/// distancia media, unos cientos de temas.
void main() {
  /// Un grafo armado a mano: [items] elementos por tema (por posición) y las
  /// uniones dadas como (a, b, coocurrencia) y (a, b) para las tensiones.
  TopicGraph graphOf(
    int count, {
    List<(int, int, int)> unions = const [],
    List<(int, int)> tensions = const [],
    List<int>? items,
  }) => TopicGraph(
    definitionId: 'tema',
    definitionName: 'Tema',
    nodes: [
      for (var i = 0; i < count; i++)
        TopicNode(
          valueId: 't$i',
          label: 'Tema $i',
          depth: 0,
          itemCount: items?[i] ?? 1,
        ),
    ],
    edges: [
      for (final (a, b, w) in unions)
        TopicEdge(
          a: a,
          b: b,
          cooccurrence: w,
          relations: 0,
          contradictions: 0,
          openContradictions: 0,
        ),
      for (final (a, b) in tensions)
        TopicEdge(
          a: a,
          b: b,
          cooccurrence: 0,
          relations: 0,
          contradictions: 1,
          openContradictions: 1,
        ),
    ],
  );

  /// Una agrupación armada a mano: los temas de cada grupo, de la comunidad
  /// más grande a la más chica; un grupo de un tema es un aislado.
  CommunityDetection detectionOf(int count, List<List<int>> groups) {
    final communityOf = Int32List(count);
    for (var id = 0; id < groups.length; id++) {
      for (final topic in groups[id]) {
        communityOf[topic] = id;
      }
    }
    return CommunityDetection(
      communityOf: communityOf,
      communities: [
        for (var id = 0; id < groups.length; id++)
          TopicCommunity(
            id: id,
            members: groups[id],
            anchor: groups[id].first,
            isIsolated: groups[id].length == 1,
          ),
      ],
      memory: const CommunityMemory.none(),
      passes: 1,
      converged: true,
      reassigned: 0,
    );
  }

  group('el panorama alejado', () {
    test(
      'cada comunidad es un nodo con su tamaño y lo que suma por dentro',
      () {
        final graph = graphOf(
          6,
          unions: [(0, 1, 3), (1, 2, 2), (3, 4, 5)],
          items: [4, 1, 2, 7, 1, 1],
        );
        final detection = detectionOf(6, [
          [0, 1, 2],
          [3, 4],
          [5],
        ]);

        final overview = aggregateCommunities(graph, detection);

        expect(overview.nodes, hasLength(3));
        final first = overview.nodes[0];
        expect(first.kind, OverviewKind.community);
        expect(first.members, [0, 1, 2]);
        expect(first.topicCount, 3);
        expect(first.itemCount, 7);
        expect(first.internalWeight, 5);
        expect(first.anchor, 0);
        expect(overview.nodes[1].internalWeight, 5);
        expect(overview.nodes[2].kind, OverviewKind.isolated);
      },
    );

    test('lo que une a dos comunidades suma, y una tensión marca la unión', () {
      final graph = graphOf(
        4,
        unions: [(0, 1, 9), (2, 3, 9), (0, 2, 2), (1, 3, 1)],
        tensions: [(1, 2)],
      );
      final detection = detectionOf(4, [
        [0, 1],
        [2, 3],
      ]);

      final overview = aggregateCommunities(graph, detection);

      final edge = overview.edges.single;
      expect((edge.a, edge.b), (0, 1));
      // 2 + 1 de coocurrencia y 3 de la contradicción.
      expect(edge.weight, 6);
      expect(edge.hasTension, isTrue);
    });

    test('los temas aislados van juntos en un solo nodo', () {
      final graph = graphOf(5, unions: [(0, 1, 2)]);
      final detection = detectionOf(5, [
        [0, 1],
        [2],
        [3],
        [4],
      ]);

      final overview = aggregateCommunities(graph, detection);

      expect(overview.nodes, hasLength(2));
      final isolated = overview.nodes.last;
      expect(isolated.kind, OverviewKind.isolated);
      expect(isolated.members, [2, 3, 4]);
      expect(isolated.communityIds, [1, 2, 3]);
      expect(isolated.anchor, isNull);
    });

    test('si no entran todas, las más chicas se juntan en un nodo de '
        'desborde', () {
      // Diez comunidades de dos temas, y un tema aislado.
      final groups = [
        for (var g = 0; g < 10; g++) [g * 2, g * 2 + 1],
        [20],
      ];
      final graph = graphOf(
        21,
        unions: [for (var g = 0; g < 10; g++) (g * 2, g * 2 + 1, 1)],
      );

      final overview = aggregateCommunities(
        graph,
        detectionOf(21, groups),
        maxNodes: 5,
      );

      expect(overview.nodes, hasLength(5));
      expect(overview.nodes.map((n) => n.kind), [
        OverviewKind.community,
        OverviewKind.community,
        OverviewKind.community,
        OverviewKind.overflow,
        OverviewKind.isolated,
      ]);
      // Las tres primeras, que son las más grandes, se muestran enteras.
      expect(overview.nodes[0].communityIds, [0]);
      final overflow = overview.nodes[3];
      expect(overflow.communityIds, [3, 4, 5, 6, 7, 8, 9]);
      expect(overflow.anchor, isNull);
      expect(overflow.topicCount, 14);
    });

    test('todos los temas caen en algún nodo, y ningún peso se pierde', () {
      final groups = [
        [0, 1, 2, 3],
        [4, 5, 6],
        [7, 8],
        [9, 10],
        [11],
        [12],
      ];
      final graph = graphOf(
        13,
        unions: [
          (0, 1, 3),
          (1, 2, 4),
          (4, 5, 2),
          (7, 8, 1),
          (9, 10, 6),
          (3, 4, 2),
          (6, 7, 1),
          (8, 9, 5),
        ],
        tensions: [(2, 5)],
      );

      final overview = aggregateCommunities(
        graph,
        detectionOf(13, groups),
        maxNodes: 4,
      );

      expect(overview.nodes.length, lessThanOrEqualTo(4));
      final members = [for (final n in overview.nodes) ...n.members]..sort();
      expect(members, [for (var i = 0; i < 13; i++) i]);
      const weights = TopicGraphWeights();
      final total = graph.edges.fold<double>(
        0,
        (sum, e) => sum + weights.of(e),
      );
      final accounted =
          overview.nodes.fold<double>(0, (sum, n) => sum + n.internalWeight) +
          overview.edges.fold<double>(0, (sum, e) => sum + e.weight);
      expect(accounted, total);
    });

    test('un tope de nodos absurdo se sube a lo mínimo que tiene sentido', () {
      final graph = graphOf(6, unions: [(0, 1, 1), (2, 3, 1), (4, 5, 1)]);
      final detection = detectionOf(6, [
        [0, 1],
        [2, 3],
        [4, 5],
      ]);

      final overview = aggregateCommunities(graph, detection, maxNodes: 0);

      expect(overview.nodes.length, lessThanOrEqualTo(3));
    });

    test('un grafo sin comunidades da un panorama vacío', () {
      final overview = aggregateCommunities(
        graphOf(0),
        CommunityDetection.empty(const CommunityMemory.none()),
      );

      expect(overview.nodes, isEmpty);
      expect(overview.edges, isEmpty);
    });
  });

  group('los temas a distancia media', () {
    test('si caben todos, van todos con todas sus uniones', () {
      final graph = graphOf(5, unions: [(0, 1, 1), (2, 3, 1), (3, 4, 1)]);

      final selection = selectTopics(graph, limit: 10);

      expect(selection.topics, [0, 1, 2, 3, 4]);
      expect(selection.edges, [0, 1, 2]);
      expect(selection.hidden, 0);
    });

    test('si no caben, los más importantes: los que más unen y más elementos '
        'tienen', () {
      // El tema 0 es el centro; el 5, sin uniones, tiene muchos elementos.
      final graph = graphOf(
        8,
        unions: [(0, 1, 4), (0, 2, 4), (0, 3, 4), (0, 4, 4)],
        items: [1, 1, 1, 1, 1, 30, 1, 1],
      );

      final selection = selectTopics(graph, limit: 3);

      expect(selection.topics, [0, 1, 5]);
      expect(selection.hidden, 5);
    });

    test(
      'las uniones que salen son las que tienen los dos extremos adentro',
      () {
        final graph = graphOf(
          6,
          unions: [(0, 1, 9), (1, 2, 9), (2, 3, 1), (3, 4, 1), (4, 5, 1)],
          items: [5, 5, 5, 1, 1, 1],
        );

        final selection = selectTopics(graph, limit: 3);

        expect(selection.topics, [0, 1, 2]);
        expect(selection.edges, [0, 1]);
      },
    );

    test('con un foco, el vecindario crece por donde más peso hay', () {
      // 0 es el foco: se une fuerte con 1 y débil con 2; 1 se une a 3.
      final graph = graphOf(
        9,
        unions: [(0, 1, 10), (0, 2, 1), (1, 3, 5), (2, 4, 1), (5, 6, 20)],
        items: [1, 1, 1, 1, 1, 1, 1, 9, 9],
      );

      final selection = selectTopics(graph, focus: {0}, limit: 3);

      // Desde el 0: el 1 (10), después el 3 (5) —vecino del 1— antes que el 2
      // (1).
      expect(selection.topics, [0, 1, 3]);
    });

    test('un foco chico se completa con los más importantes del resto', () {
      final graph = graphOf(
        6,
        unions: [(0, 1, 2), (2, 3, 9), (3, 4, 9)],
        items: [1, 1, 1, 1, 1, 1],
      );

      final selection = selectTopics(graph, focus: {0}, limit: 4);

      // 0 y 1 son todo lo que hay conectado con el foco; siguen los de mayor
      // importancia: el 3 (18 + 1) y el 2 o el 4 (9 + 1), por posición.
      expect(selection.topics, [0, 1, 2, 3]);
    });

    test('un foco fuera de rango se ignora', () {
      final graph = graphOf(4, unions: [(0, 1, 1)]);

      final selection = selectTopics(graph, focus: {-1, 99}, limit: 2);

      expect(selection.topics, hasLength(2));
    });

    test(
      'con un foco elige lo mismo aunque los temas vengan en otro orden',
      () {
        List<int> chosenIds(List<int> order) {
          // El mismo grafo con los temas renumerados según `order`.
          final position = {for (var i = 0; i < order.length; i++) order[i]: i};
          final base = [
            (0, 1, 10),
            (0, 2, 1),
            (1, 3, 5),
            (2, 4, 1),
            (5, 6, 20),
          ];
          final graph = graphOf(
            7,
            unions: [
              for (final (a, b, w) in base)
                if (position[a]! < position[b]!)
                  (position[a]!, position[b]!, w)
                else
                  (position[b]!, position[a]!, w),
            ],
          );
          final selection = selectTopics(
            graph,
            focus: {position[0]!},
            limit: 3,
          );
          return [for (final t in selection.topics) order[t]]..sort();
        }

        expect(chosenIds([0, 1, 2, 3, 4, 5, 6]), [0, 1, 3]);
        expect(chosenIds([6, 5, 4, 3, 2, 1, 0]), [0, 1, 3]);
      },
    );

    test('con un tope de cero no elige nada', () {
      final selection = selectTopics(graphOf(3), limit: 0);

      expect(selection.topics, isEmpty);
      expect(selection.hidden, 3);
    });
  });

  group('el vecindario de un foco', () {
    test('el foco y lo que se une directamente a él, y nada de más lejos', () {
      // 0 ─ 1 ─ 2 (el 2 está a dos saltos del 0), 3 ─ 4 aparte.
      final graph = graphOf(5, unions: [(0, 1, 5), (1, 2, 5), (3, 4, 5)]);

      final selection = selectNeighborhood(graph, focus: {0});

      expect(selection.topics, [0, 1]);
      expect(selection.edges, [0]);
      expect(selection.hidden, 0);
    });

    test('con un foco de varios temas, todos los suyos y sus vecinos', () {
      final graph = graphOf(
        6,
        unions: [(0, 1, 5), (1, 2, 5), (2, 3, 5), (4, 5, 5)],
      );

      final selection = selectNeighborhood(graph, focus: {1, 2});

      expect(selection.topics, [0, 1, 2, 3]);
      expect(selection.edges, [0, 1, 2]);
    });

    test('si no caben los vecinos, entran los que más unen al foco', () {
      final graph = graphOf(4, unions: [(0, 1, 5), (0, 2, 1), (0, 3, 3)]);

      final selection = selectNeighborhood(graph, focus: {0}, limit: 3);

      expect(selection.topics, [0, 1, 3]);
      expect(selection.hidden, 1);
    });

    test(
      'si el foco solo ya pasa el tope, entran los más importantes de él',
      () {
        // Cinco temas en el foco, los del final con más elementos.
        final graph = graphOf(5, items: [1, 1, 1, 9, 8]);

        final selection = selectNeighborhood(
          graph,
          focus: {0, 1, 2, 3, 4},
          limit: 3,
        );

        expect(selection.topics, [0, 3, 4]);
        expect(selection.hidden, 2);
      },
    );

    test('un foco fuera de rango o vacío no elige nada', () {
      final graph = graphOf(3, unions: [(0, 1, 1)]);

      expect(selectNeighborhood(graph, focus: {}).topics, isEmpty);
      expect(selectNeighborhood(graph, focus: {-1, 99}).topics, isEmpty);
    });
  });

  test('la fuerza de un tema es la suma de los pesos de sus uniones', () {
    final graph = graphOf(
      3,
      unions: [(0, 1, 2), (1, 2, 3)],
      tensions: [(0, 2)],
    );

    final strength = topicStrength(graph, const TopicGraphWeights());

    expect(strength, [2 + 3, 2 + 3, 3 + 3]);
  });
}
