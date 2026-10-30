import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/services/bridge_finder.dart';
import 'package:sinapsis/features/map/domain/services/community_links.dart';

import 'insights_fixtures.dart';

/// Los puentes (F44): los temas que más unen comunidades distintas, con su
/// costo lineal en las uniones.
void main() {
  BridgeAnalysis bridgesOf(
    BuiltMap map, {
    int limit = kMaxBridges,
    int maxJoins = kMaxBridgeJoins,
  }) => findBridges(
    map.adjacency,
    CommunityLinks.of(map.adjacency, map.detection),
    limit: limit,
    maxJoins: maxJoins,
  );

  List<String> idsOf(BuiltMap map, BridgeAnalysis analysis) => [
    for (final bridge in analysis.bridges)
      map.graph.nodes[bridge.topic].valueId,
  ];

  /// A = a1·a2·a3, B = b1·b2·b3 y C = c1·c2. Entre A y B hay diez uniones:
  /// tres pasan por a1–b1 y siete por a2–b2. Entre A y C, dos, y las dos por
  /// a3–c1: es el único camino.
  BuiltMap threeCommunities() => mapOf(
    inputOf(
      ['a1', 'a2', 'a3', 'b1', 'b2', 'b3', 'c1', 'c2'],
      [
        ['a1', 'a2'],
        ['a2', 'a3'],
        ['b1', 'b2'],
        ['b2', 'b3'],
        ['c1', 'c2'],
        ...repeat(3, ['a1', 'b1']),
        ...repeat(7, ['a2', 'b2']),
        ...repeat(2, ['a3', 'c1']),
      ],
    ),
    {'a1': 1, 'a2': 1, 'a3': 1, 'b1': 2, 'b2': 2, 'b3': 2, 'c1': 3, 'c2': 3},
  );

  test('pesa lo que une por la parte que lleva de todo lo que une a las dos '
      'comunidades: el único camino vale más que uno de muchos', () {
    final map = threeCommunities();
    final analysis = bridgesOf(map);

    // a2 y b2 llevan siete de diez (7 × 0,7); a3 y c1, todo lo de A con C
    // (2 × 1); a1 y b1, tres de diez (3 × 0,3). Sin la parte, a1 iría antes
    // que a3.
    expect(idsOf(map, analysis), ['a2', 'b2', 'a3', 'c1', 'a1', 'b1']);
    final a3 = analysis.bridges[2];
    expect(a3.score, closeTo(2, 1e-9));
    expect(a3.communityId, 1);
    expect(a3.joins.single.communityId, 3);
    expect(a3.joins.single.isSole, isTrue);
    expect(a3.soleCount, 1);

    final a1 = analysis.bridges[4];
    expect(a1.score, closeTo(0.9, 1e-9));
    expect(a1.joins.single.share, closeTo(0.3, 1e-9));
    expect(a1.joins.single.isSole, isFalse);
    expect(a1.soleCount, 0);

    expect(analysis.candidates, 6);
    expect(analysis.isBridge(map.graph.indexOf('a3')!), isTrue);
    expect(analysis.isBridge(map.graph.indexOf('b3')!), isFalse);
  });

  test('un tema solo que cuelga de UNA comunidad no une nada; uno solo que '
      'toca dos, sí', () {
    final map = mapOf(
      inputOf(
        ['a1', 'a2', 'b1', 'b2', 'satelite', 'enlace'],
        [
          ['a1', 'a2'],
          ['b1', 'b2'],
          ['satelite', 'a1'],
          ['enlace', 'a2'],
          ['enlace', 'b2'],
        ],
      ),
      {'a1': 1, 'a2': 1, 'b1': 2, 'b2': 2, 'satelite': 3, 'enlace': 4},
    );

    final analysis = bridgesOf(map);
    final ids = idsOf(map, analysis);

    expect(ids, contains('enlace'));
    expect(ids, isNot(contains('satelite')));
    final enlace = analysis.bridges[ids.indexOf('enlace')];
    expect(enlace.joinedCount, 2);
    expect(enlace.soleCount, 2);
    // a1 sí: une su comunidad con la del satélite.
    expect(ids, contains('a1'));
  });

  test('con una sola comunidad no hay puentes', () {
    final map = mapOf(
      inputOf(
        ['a', 'b', 'c'],
        [
          ['a', 'b'],
          ['b', 'c'],
        ],
      ),
      {'a': 1, 'b': 1, 'c': 1},
    );

    final analysis = bridgesOf(map);

    expect(analysis.bridges, isEmpty);
    expect(analysis.candidates, 0);
  });

  test('entrega los que pide, y de cada uno, las uniones más fuertes hasta '
      'el tope, sin perder la cuenta', () {
    final spokes = [for (var i = 0; i < 10; i++) 'k$i'];
    final map = mapOf(
      inputOf(
        ['h', 'h2', ...spokes],
        [
          ['h', 'h2'],
          for (var i = 0; i < 10; i++) ...repeat(i + 1, ['h', 'k$i']),
        ],
      ),
      {'h': 100, 'h2': 100, for (var i = 0; i < 10; i++) 'k$i': i},
    );

    final analysis = bridgesOf(map, limit: 1, maxJoins: 4);

    final hub = analysis.bridges.single;
    expect(map.graph.nodes[hub.topic].valueId, 'h');
    expect(hub.joinedCount, 10);
    expect([for (final j in hub.joins) j.communityId], [9, 8, 7, 6]);
    expect([for (final j in hub.joins) j.weight], [10, 9, 8, 7]);
    // Los rayos cuelgan cada uno de una sola comunidad: no son puentes.
    expect(analysis.candidates, 1);
  });

  test('el costo es lineal: cada unión se mira dos veces para los pares y '
      'para los puntajes, y otra solo en los puentes que se entregan', () {
    final map = threeCommunities();
    final adjacency = map.adjacency;

    final analysis = bridgesOf(map, limit: 2);

    var chosenDegree = 0;
    for (final bridge in analysis.bridges) {
      chosenDegree += adjacency.degreeOf(bridge.topic);
    }
    expect(analysis.visits, 2 * adjacency.neighbors.length + chosenDegree);
  });

  test('es determinista: el mismo mapa da los mismos puentes', () {
    String signature(BridgeAnalysis a) => [
      for (final b in a.bridges)
        '${b.topic}:${b.score}:${[for (final j in b.joins) j.communityId]}',
    ].join(' ');

    expect(
      signature(bridgesOf(threeCommunities())),
      signature(bridgesOf(threeCommunities())),
    );
  });
}
