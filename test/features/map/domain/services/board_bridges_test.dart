import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_bridges.dart';

/// Los temas puente del Resumen (F44, paso 3): los que unen comunidades
/// distintas y los que, si se sacaran, dejarían partes sueltas. Grafos y
/// comunidades armados a mano, para no depender de cómo agrupa el detector.
void main() {
  /// Un grafo de [labels] con las uniones [edges] (cada una pesa [weights] o 1
  /// documento compartido), y las comunidades [groups]: la identidad de cada
  /// tema, por posición.
  ({TopicGraph graph, CommunityDetection detection}) build(
    List<String> labels,
    List<(int, int)> edges,
    List<int> groups, {
    Map<(int, int), int> weights = const {},
  }) {
    final graph = TopicGraph(
      definitionId: 'tema',
      definitionName: 'Tema',
      nodes: [
        for (final label in labels)
          TopicNode(valueId: label, label: label, depth: 0, itemCount: 1),
      ],
      edges: [
        for (final (a, b) in edges)
          TopicEdge(
            a: a < b ? a : b,
            b: a < b ? b : a,
            cooccurrence: weights[(a, b)] ?? 1,
            relations: 0,
            contradictions: 0,
            openContradictions: 0,
          ),
      ],
    );
    final ids = groups.toSet().toList()..sort();
    final degree = List.filled(labels.length, 0);
    for (final (a, b) in edges) {
      degree[a]++;
      degree[b]++;
    }
    final detection = CommunityDetection(
      communityOf: Int32List.fromList(groups),
      communities: [
        for (final id in ids)
          TopicCommunity(
            id: id,
            members: [
              for (var i = 0; i < groups.length; i++)
                if (groups[i] == id) i,
            ],
            // La primera de sus posiciones: lo que nombra la comunidad.
            anchor: groups.indexOf(id),
            isIsolated:
                groups.where((g) => g == id).length == 1 &&
                degree[groups.indexOf(id)] == 0,
          ),
      ],
      memory: const CommunityMemory.none(),
      passes: 1,
      converged: true,
      reassigned: 0,
    );
    return (graph: graph, detection: detection);
  }

  List<String> labelsOf(List<BoardBridge> bridges) => [
    for (final b in bridges) b.topic.label,
  ];

  test('un grafo sin uniones no tiene puentes', () {
    final (:graph, :detection) = build(['a', 'b'], const [], [0, 1]);

    expect(bridgesOf(graph, detection), isEmpty);
  });

  test('dos comunidades unidas por una arista: los dos extremos son puentes '
      'y dicen con qué comunidad se unen', () {
    // a ─ b    c ─ d, y b ─ c entre las dos.
    final (:graph, :detection) = build(
      ['a', 'b', 'c', 'd'],
      const [(0, 1), (1, 2), (2, 3)],
      [0, 0, 1, 1],
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['b', 'c']);
    expect([for (final c in bridges[0].joins) c.id], [1]);
    expect([for (final c in bridges[1].joins) c.id], [0]);
    // Y además, sacar b o c parte la cadena en dos.
    expect(bridges[0].parts, 2);
    expect(bridges[1].crossWeight, 1);
  });

  test('el que toca más comunidades va primero', () {
    // hub une las tres comunidades; a, b e y tocan solo una ajena —la de
    // hub—, pero sin y, x queda suelto: y va antes que a y b.
    final (:graph, :detection) = build(
      ['a', 'b', 'hub', 'x', 'y'],
      const [(2, 0), (2, 1), (2, 4), (3, 4), (0, 1)],
      [0, 0, 1, 2, 2],
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['hub', 'y', 'a', 'b']);
    expect(bridges.first.joins, hasLength(2));
    expect(bridges[1].parts, 2);
    expect(bridges[2].parts, 0);
  });

  test('a igual cantidad de comunidades, las uniones más pesadas primero; y '
      'las comunidades de cada uno, la más unida primero', () {
    // p y q tocan la comunidad de r; p con más peso.
    final (:graph, :detection) = build(
      ['p', 'q', 'r', 's'],
      const [(0, 2), (1, 2), (0, 1), (0, 3), (1, 3), (2, 3)],
      [0, 0, 1, 2],
      weights: const {(0, 2): 5, (0, 3): 3},
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['p', 'r', 's', 'q']);
    expect([for (final c in bridges.first.joins) c.id], [1, 2]);
  });

  test('dentro de una sola comunidad, un punto de corte es puente por las '
      'partes que dejaría', () {
    // Una estrella: c en el centro, con tres puntas.
    final (:graph, :detection) = build(
      ['a', 'b', 'c', 'd'],
      const [(2, 0), (2, 1), (2, 3)],
      [0, 0, 0, 0],
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['c']);
    expect(bridges.single.joins, isEmpty);
    expect(bridges.single.parts, 3);
  });

  test('un ciclo no tiene puntos de corte: nada se separa al sacar uno', () {
    final (:graph, :detection) = build(
      ['a', 'b', 'c', 'd'],
      const [(0, 1), (1, 2), (2, 3), (3, 0)],
      [0, 0, 0, 0],
    );

    expect(bridgesOf(graph, detection), isEmpty);
  });

  test('un punto de corte que no es la raíz del recorrido cuenta lo de '
      'arriba como otra parte', () {
    // a ─ b ─ c, y b ─ d: b, sin ser la raíz, deja tres partes.
    final (:graph, :detection) = build(
      ['a', 'b', 'c', 'd'],
      const [(0, 1), (1, 2), (1, 3)],
      [0, 0, 0, 0],
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['b']);
    expect(bridges.single.parts, 3);
  });

  test('un tema del que cuelga un ciclo también corta: lo de abajo vuelve '
      'hasta él, no más arriba', () {
    // a ─ b, y el triángulo b ─ c ─ d ─ b: sin b, a queda solo.
    final (:graph, :detection) = build(
      ['a', 'b', 'c', 'd'],
      const [(0, 1), (1, 2), (2, 3), (3, 1)],
      [0, 0, 0, 0],
    );

    final bridges = bridgesOf(graph, detection);

    expect(labelsOf(bridges), ['b']);
    expect(bridges.single.parts, 2);
  });

  test('respeta el tope', () {
    const n = 30;
    final (:graph, :detection) = build(
      [for (var i = 0; i < n; i++) 't$i'],
      [for (var i = 0; i < n - 1; i++) (i, i + 1)],
      [for (var i = 0; i < n; i++) i],
    );

    expect(bridgesOf(graph, detection, limit: 5), hasLength(5));
  });

  test('una cadena larga no agota la pila: el recorrido es con una pila '
      'propia', () {
    const n = 20000;
    final (:graph, :detection) = build(
      [for (var i = 0; i < n; i++) 't$i'],
      [for (var i = 0; i < n - 1; i++) (i, i + 1)],
      List.filled(n, 0),
    );

    final bridges = bridgesOf(graph, detection, limit: n);

    // Todos menos las dos puntas son puntos de corte.
    expect(bridges, hasLength(n - 2));
    expect(bridges.every((b) => b.parts == 2), isTrue);
  });
}
