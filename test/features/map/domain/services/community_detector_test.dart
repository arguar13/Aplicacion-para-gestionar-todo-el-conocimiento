import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';

/// Las comunidades de temas (F14, D1): propagación de etiquetas ponderada,
/// determinista, que arranca en caliente y conserva las identidades.
void main() {
  /// Un grafo armado a mano: los temas en el orden dado, sus uniones por
  /// coocurrencia con el peso indicado, sus tensiones y sus padres.
  TopicGraph graphOf(
    List<String> ids, {
    List<(String, String, int)> unions = const [],
    List<(String, String)> tensions = const [],
    Map<String, String> parents = const {},
  }) {
    final position = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    TopicEdge edge(String x, String y, {int co = 0, int contra = 0}) {
      final a = position[x]!;
      final b = position[y]!;
      return TopicEdge(
        a: a < b ? a : b,
        b: a < b ? b : a,
        cooccurrence: co,
        relations: 0,
        contradictions: contra,
        openContradictions: contra,
      );
    }

    return TopicGraph(
      definitionId: 'tema',
      definitionName: 'Tema',
      nodes: [
        for (final id in ids)
          TopicNode(
            valueId: id,
            label: id,
            parentId: parents[id],
            depth: parents.containsKey(id) ? 1 : 0,
            itemCount: 1,
          ),
      ],
      edges: [
        for (final (x, y, w) in unions) edge(x, y, co: w),
        for (final (x, y) in tensions) edge(x, y, contra: 1),
      ],
    );
  }

  /// Los temas de [ids] unidos de a pares, todos con todos, con [weight].
  List<(String, String, int)> clique(List<String> ids, int weight) => [
    for (var i = 0; i < ids.length; i++)
      for (var j = i + 1; j < ids.length; j++) (ids[i], ids[j], weight),
  ];

  /// Las comunidades como conjuntos de valores: lo que no depende de qué
  /// identidad numérica llevó cada una.
  Set<Set<String>> partitionOf(TopicGraph graph, CommunityDetection result) => {
    for (final community in result.communities)
      {for (final m in community.members) graph.nodes[m].valueId},
  };

  int idOf(TopicGraph graph, CommunityDetection result, String valueId) =>
      result.communityOf[graph.indexOf(valueId)!];

  group('las comunidades', () {
    test(
      'dos grupos densos unidos por un puente débil son dos comunidades',
      () {
        final a = ['a1', 'a2', 'a3', 'a4', 'a5'];
        final b = ['b1', 'b2', 'b3', 'b4', 'b5'];
        final graph = graphOf(
          [...a, ...b],
          unions: [...clique(a, 5), ...clique(b, 5), ('a1', 'b1', 1)],
        );

        final result = detectCommunities(graph);

        expect(partitionOf(graph, result), {a.toSet(), b.toSet()});
        expect(result.converged, isTrue);
      },
    );

    test('tres grupos, aunque haya uniones entre ellos', () {
      final groups = [
        ['a1', 'a2', 'a3', 'a4'],
        ['b1', 'b2', 'b3', 'b4'],
        ['c1', 'c2', 'c3', 'c4'],
      ];
      final graph = graphOf(
        [for (final g in groups) ...g],
        unions: [
          for (final g in groups) ...clique(g, 6),
          ('a1', 'b1', 1),
          ('b2', 'c2', 1),
          ('c3', 'a3', 1),
        ],
      );

      expect(partitionOf(graph, detectCommunities(graph)), {
        for (final g in groups) g.toSet(),
      });
    });

    test('un tema sin ninguna unión es su propia comunidad, aislada', () {
      final graph = graphOf(['a', 'b', 'solo'], unions: [('a', 'b', 2)]);

      final result = detectCommunities(graph);

      final solo = result.communityById(idOf(graph, result, 'solo'))!;
      expect(solo.members, [graph.indexOf('solo')]);
      expect(solo.isIsolated, isTrue);
      final pair = result.communityById(idOf(graph, result, 'a'))!;
      expect(pair.members, hasLength(2));
      expect(pair.isIsolated, isFalse);
    });

    test('la comunidad la nombra el tema más unido', () {
      final graph = graphOf(
        ['a', 'b', 'c', 'centro'],
        unions: [('a', 'centro', 3), ('b', 'centro', 3), ('c', 'centro', 3)],
      );

      final result = detectCommunities(graph);

      expect(result.communities, hasLength(1));
      expect(graph.nodes[result.communities.single.anchor].valueId, 'centro');
    });

    test('un grafo sin temas da un resultado vacío', () {
      final result = detectCommunities(graphOf(const []));

      expect(result.communities, isEmpty);
      expect(result.communityOf, isEmpty);
      expect(result.converged, isTrue);
      expect(result.passes, 0);
    });

    test('un grafo sin uniones deja a cada tema solo', () {
      final graph = graphOf(['a', 'b', 'c']);

      final result = detectCommunities(graph);

      expect(result.communities, hasLength(3));
      expect(result.communities.every((c) => c.isIsolated), isTrue);
    });
  });

  group('los pesos', () {
    /// x se une a dos temas de un grupo por coocurrencia y a uno de otro por
    /// una contradicción.
    TopicGraph tensionGraph() => graphOf(
      ['x', 'y1', 'y2', 'y3', 'y4', 'z1', 'z2', 'z3', 'z4'],
      unions: [
        ...clique(['y1', 'y2', 'y3', 'y4'], 10),
        ...clique(['z1', 'z2', 'z3', 'z4'], 10),
        ('x', 'y1', 1),
        ('x', 'y2', 1),
      ],
      tensions: [('x', 'z1')],
    );

    test('una contradicción pesa más que dos coocurrencias', () {
      final graph = tensionGraph();

      final result = detectCommunities(graph);

      expect(
        idOf(graph, result, 'x'),
        idOf(graph, result, 'z1'),
        reason: '3 de la contradicción contra 1 + 1 de las coocurrencias',
      );
    });

    test('con otros pesos, gana el otro lado', () {
      final graph = tensionGraph();

      final result = detectCommunities(
        graph,
        weights: const TopicGraphWeights(contradiction: 0.5),
      );

      expect(idOf(graph, result, 'x'), idOf(graph, result, 'y1'));
    });

    test('un tema se pega a su padre en la jerarquía', () {
      final ids = ['padre', 'q1', 'q2', 'hijo'];
      final graph = graphOf(
        ids,
        unions: clique(['padre', 'q1', 'q2'], 4),
        parents: {'hijo': 'padre'},
      );

      final withHierarchy = detectCommunities(graph);
      final without = detectCommunities(graph, hierarchyWeight: 0);

      expect(
        idOf(graph, withHierarchy, 'hijo'),
        idOf(graph, withHierarchy, 'padre'),
      );
      expect(
        withHierarchy
            .communityById(idOf(graph, withHierarchy, 'hijo'))!
            .isIsolated,
        isFalse,
      );
      expect(
        without.communityById(idOf(graph, without, 'hijo'))!.isIsolated,
        isTrue,
      );
    });
  });

  group('el orden', () {
    test('el mismo grafo da siempre las mismas comunidades', () {
      final a = ['a1', 'a2', 'a3'];
      final b = ['b1', 'b2', 'b3'];
      final graph = graphOf(
        [...a, ...b],
        unions: [...clique(a, 2), ...clique(b, 2), ('a2', 'b2', 1)],
      );

      final first = detectCommunities(graph);
      final second = detectCommunities(graph);

      expect(second.communityOf, first.communityOf);
      expect(second.passes, first.passes);
    });

    test('los temas en otro orden dan la misma partición', () {
      final ids = [for (var i = 0; i < 24; i++) 't$i'];
      final random = Random(5);
      final unions = <(String, String, int)>[];
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final sameGroup = i ~/ 8 == j ~/ 8;
          if (random.nextDouble() < (sameGroup ? 0.7 : 0.03)) {
            unions.add((ids[i], ids[j], 1 + random.nextInt(3)));
          }
        }
      }

      final forward = graphOf(ids, unions: unions);
      final backward = graphOf(ids.reversed.toList(), unions: unions);

      expect(
        partitionOf(backward, detectCommunities(backward)),
        partitionOf(forward, detectCommunities(forward)),
      );
    });
  });

  group('las identidades', () {
    test('en el primer cálculo van de 0, de la comunidad más grande a la más '
        'chica', () {
      final graph = graphOf(
        ['s', 'a1', 'a2', 'a3', 'b1', 'b2'],
        unions: [
          ...clique(['a1', 'a2', 'a3'], 3),
          ('b1', 'b2', 3),
        ],
      );

      final result = detectCommunities(graph);

      expect([for (final c in result.communities) c.id], [0, 1, 2]);
      expect([for (final c in result.communities) c.members.length], [3, 2, 1]);
      expect(result.reassigned, 0);
      expect(result.memory.nextId, 3);
    });

    test('recalcular sin cambios conserva todo: en una pasada y sin mover '
        'a nadie', () {
      final a = ['a1', 'a2', 'a3', 'a4'];
      final b = ['b1', 'b2', 'b3', 'b4'];
      final graph = graphOf(
        [...a, ...b],
        unions: [...clique(a, 4), ...clique(b, 4), ('a1', 'b1', 1)],
      );
      final cold = detectCommunities(graph);

      final warm = detectCommunities(graph, previous: cold.memory);

      expect(warm.communityOf, cold.communityOf);
      expect(warm.reassigned, 0);
      expect(warm.passes, 1);
      expect(warm.memory.nextId, cold.memory.nextId);
    });

    test('un tema nuevo se suma a la comunidad de sus vecinos y nadie más se '
        'mueve', () {
      final a = ['a1', 'a2', 'a3', 'a4'];
      final b = ['b1', 'b2', 'b3', 'b4'];
      final before = graphOf(
        [...a, ...b],
        unions: [...clique(a, 4), ...clique(b, 4), ('a1', 'b1', 1)],
      );
      final cold = detectCommunities(before);

      final after = graphOf(
        [...a, ...b, 'b0'],
        unions: [
          ...clique(a, 4),
          ...clique(b, 4),
          ('a1', 'b1', 1),
          ('b0', 'b2', 2),
          ('b0', 'b3', 2),
        ],
      );
      final warm = detectCommunities(after, previous: cold.memory);

      expect(idOf(after, warm, 'b0'), idOf(before, cold, 'b1'));
      for (final id in [...a, ...b]) {
        expect(idOf(after, warm, id), idOf(before, cold, id), reason: id);
      }
      expect(warm.reassigned, 0);
      expect(warm.memory.nextId, cold.memory.nextId);
    });

    test('una comunidad que se parte en dos conserva su identidad en la '
        'parte más grande y la otra recibe una nueva', () {
      const memory = CommunityMemory(
        byValueId: {'a': 7, 'b': 7, 'c': 7, 'd': 7, 'e': 7},
        nextId: 8,
      );
      // Dos zonas sin ninguna unión entre ellas: a-b-c y d-e.
      final graph = graphOf(
        ['a', 'b', 'c', 'd', 'e'],
        unions: [('a', 'b', 2), ('b', 'c', 2), ('a', 'c', 2), ('d', 'e', 2)],
      );

      final result = detectCommunities(graph, previous: memory);

      expect(idOf(graph, result, 'a'), 7);
      expect(idOf(graph, result, 'b'), 7);
      expect(idOf(graph, result, 'c'), 7);
      expect(idOf(graph, result, 'd'), 8);
      expect(idOf(graph, result, 'e'), 8);
      expect(result.reassigned, 2);
      expect(result.memory.nextId, 9);
    });

    test('si dos comunidades se funden, una conserva su identidad y la otra '
        'desaparece', () {
      final a = ['a1', 'a2', 'a3'];
      final b = ['b1', 'b2', 'b3'];
      final separate = graphOf(
        [...a, ...b],
        unions: [...clique(a, 3), ...clique(b, 3)],
      );
      final cold = detectCommunities(separate);
      expect(cold.communities, hasLength(2));

      // Ahora hay muchas uniones entre ellas.
      final joined = graphOf(
        [...a, ...b],
        unions: [
          ...clique(a, 3),
          ...clique(b, 3),
          for (final x in a)
            for (final y in b) (x, y, 9),
        ],
      );
      final warm = detectCommunities(joined, previous: cold.memory);

      expect(warm.communities, hasLength(1));
      expect(
        cold.communities.map((c) => c.id),
        contains(warm.communities.single.id),
      );
    });

    test('la memoria no se cuelga de los temas que ya no están', () {
      final graph = graphOf(['a', 'b'], unions: [('a', 'b', 1)]);
      const memory = CommunityMemory(
        byValueId: {'a': 3, 'b': 3, 'borrado': 3, 'otro': 4},
        nextId: 5,
      );

      final result = detectCommunities(graph, previous: memory);

      expect(result.communities.single.id, 3);
      expect(result.memory.byValueId.keys, unorderedEquals(['a', 'b']));
    });
  });

  group('un grafo grande', () {
    /// [groups] grupos de [size] temas: dentro de un grupo se unen con
    /// probabilidad [inner]; entre grupos, [outer] uniones al azar.
    ({TopicGraph graph, List<List<String>> groups}) planted({
      required int groups,
      required int size,
      required double inner,
      required int outer,
      int seed = 3,
    }) {
      final random = Random(seed);
      final all = [
        for (var g = 0; g < groups; g++)
          [for (var i = 0; i < size; i++) 'g${g}_$i'],
      ];
      final ids = [for (final g in all) ...g];
      final seen = <String>{};
      final unions = <(String, String, int)>[];
      for (final g in all) {
        for (var i = 0; i < size; i++) {
          for (var j = i + 1; j < size; j++) {
            if (random.nextDouble() < inner) {
              unions.add((g[i], g[j], 1 + random.nextInt(4)));
            }
          }
        }
      }
      while (seen.length < outer) {
        final x = ids[random.nextInt(ids.length)];
        final y = ids[random.nextInt(ids.length)];
        if (x == y || x.split('_').first == y.split('_').first) continue;
        final key = x.compareTo(y) < 0 ? '$x|$y' : '$y|$x';
        if (seen.add(key)) unions.add((x, y, 1));
      }
      return (graph: graphOf(ids, unions: unions), groups: all);
    }

    /// Qué parte de los temas quedó en la comunidad mayoritaria de su grupo.
    double purity(
      TopicGraph graph,
      CommunityDetection result,
      List<List<String>> groups,
    ) {
      var right = 0;
      for (final group in groups) {
        final counts = <int, int>{};
        for (final id in group) {
          counts.update(
            idOf(graph, result, id),
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
        right += counts.values.reduce(max);
      }
      return right / groups.fold<int>(0, (sum, g) => sum + g.length);
    }

    test(
      'recupera los grupos plantados de 2.000 temas, converge y no tarda',
      () {
        final data = planted(groups: 20, size: 100, inner: 0.1, outer: 2000);

        final watch = Stopwatch()..start();
        final result = detectCommunities(data.graph);
        watch.stop();

        expect(result.converged, isTrue);
        expect(purity(data.graph, result, data.groups), greaterThan(0.95));
        expect(
          result.communities.where((c) => !c.isIsolated),
          hasLength(inInclusiveRange(20, 24)),
        );
        // Muy por encima de lo que tarda: es para que un cálculo que se vuelva
        // cuadrático no pase inadvertido, no una medición.
        expect(watch.elapsedMilliseconds, lessThan(3000));
      },
    );

    test('tras un cambio chico, en caliente se mueven pocos temas y hace falta '
        'una o dos pasadas', () {
      final data = planted(groups: 10, size: 60, inner: 0.15, outer: 400);
      final cold = detectCommunities(data.graph);

      // Se suman cinco uniones entre grupos, con más peso que las de siempre.
      final extra = [
        (data.groups[0][0], data.groups[1][0], 3),
        (data.groups[2][1], data.groups[3][1], 3),
        (data.groups[4][2], data.groups[5][2], 3),
        (data.groups[6][3], data.groups[7][3], 3),
        (data.groups[8][4], data.groups[9][4], 3),
      ];
      final ids = [for (final n in data.graph.nodes) n.valueId];
      final changed = graphOf(
        ids,
        unions: [
          for (final e in data.graph.edges)
            (ids[e.a], ids[e.b], e.cooccurrence),
          ...extra,
        ],
      );

      final warm = detectCommunities(changed, previous: cold.memory);
      final fromScratch = detectCommunities(changed);

      expect(warm.reassigned, lessThan(10));
      expect(warm.passes, lessThanOrEqualTo(3));
      expect(warm.passes, lessThanOrEqualTo(fromScratch.passes));
      expect(warm.converged, isTrue);
    });
  });
}
