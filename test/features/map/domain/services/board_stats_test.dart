import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_stats.dart';

/// Lo que el tablero saca del grafo de temas (F14).
void main() {
  TopicGraph graphOf(
    List<int> items, {
    List<(int, int, int)> unions = const [],
    List<(int, int)> tensions = const [],
  }) => TopicGraph(
    definitionId: 'tema',
    definitionName: 'Tema',
    nodes: [
      for (var i = 0; i < items.length; i++)
        TopicNode(
          valueId: 't$i',
          label: 'Tema $i',
          depth: 0,
          itemCount: items[i],
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

  CommunityDetection detectionOf(int count, List<List<int>> groups) =>
      CommunityDetection(
        communityOf: Int32List(count),
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

  test('los temas más densos: los de más elementos, sin los vacíos', () {
    final graph = graphOf([3, 9, 0, 9, 1]);

    final stats = boardStatsOf(
      graph,
      detectionOf(5, [
        [0],
        [1],
        [2],
        [3],
        [4],
      ]),
    );

    // Empate entre el 1 y el 3: manda la posición.
    expect(
      [for (final t in stats.densest) t.valueId],
      ['t1', 't3', 't0', 't4'],
    );
  });

  test('los pares más conectados: por peso, con la tensión que pesa más', () {
    final graph = graphOf(
      [1, 1, 1, 1],
      unions: [(0, 1, 2), (1, 2, 5), (2, 3, 1)],
      tensions: [(0, 3)],
    );

    final stats = boardStatsOf(
      graph,
      detectionOf(4, [
        [0, 1, 2, 3],
      ]),
    );

    expect(
      [
        for (final p in stats.connected)
          (p.first.valueId, p.second.valueId, p.weight),
      ],
      [
        ('t1', 't2', 5.0),
        ('t0', 't3', 3.0),
        ('t0', 't1', 2.0),
        ('t2', 't3', 1.0),
      ],
    );
    expect(stats.connected[1].edge.isTension, isTrue);
  });

  test('los aislados son los temas sin ninguna unión, los de más elementos '
      'primero', () {
    final graph = graphOf([1, 1, 4, 0, 4], unions: [(0, 1, 1)]);

    final stats = boardStatsOf(
      graph,
      detectionOf(5, [
        [0, 1],
        [2],
        [3],
        [4],
      ]),
    );

    expect([for (final t in stats.isolated) t.valueId], ['t2', 't4', 't3']);
    expect(stats.isolatedCount, 3);
  });

  test('las comunidades no cuentan a los aislados', () {
    final graph = graphOf([1, 1, 1, 1, 1], unions: [(0, 1, 1), (2, 3, 1)]);

    final stats = boardStatsOf(
      graph,
      detectionOf(5, [
        [0, 1],
        [2, 3],
        [4],
      ]),
    );

    expect(stats.communityCount, 2);
    expect(stats.topicCount, 5);
  });

  test(
    'cada lista se corta en el límite, y aun así dice cuántos aislados hay',
    () {
      final graph = graphOf([for (var i = 0; i < 20; i++) i + 1]);

      final stats = boardStatsOf(
        graph,
        detectionOf(20, [
          for (var i = 0; i < 20; i++) [i],
        ]),
        limit: 5,
      );

      expect(stats.densest, hasLength(5));
      expect(stats.isolated, hasLength(5));
      expect(stats.isolatedCount, 20);
    },
  );

  test('un grafo vacío da listas vacías', () {
    final stats = boardStatsOf(
      graphOf(const []),
      CommunityDetection.empty(const CommunityMemory.none()),
    );

    expect(stats.topicCount, 0);
    expect(stats.densest, isEmpty);
    expect(stats.connected, isEmpty);
    expect(stats.isolated, isEmpty);
    expect(stats.communityCount, 0);
  });
}
