import 'dart:collection';
import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';

/// Cuántas comunidades vecinas se nombran de cada una, como mucho.
const kCommunityNeighbors = 5;

/// Lo que une a cada par de comunidades (F44): la suma de las uniones entre sus
/// temas y cuántas son.
///
/// Solo hay un par por cada dos comunidades que de verdad se tocan —a lo sumo
/// tantos como uniones—, nunca una tabla de comunidad por comunidad: con dos
/// mil temas aislados serían cuatro millones de casilleros vacíos.
class CommunityLinks {
  CommunityLinks._({
    required this.denseOf,
    required this.ids,
    required this.communityOfTopic,
    required HashMap<int, double> weight,
    required HashMap<int, int> count,
    required List<List<CommunityLink>> neighbors,
    required this.visits,
  }) : _weight = weight,
       _count = count,
       _neighbors = neighbors;

  /// Las uniones de [adjacency] entre temas de comunidades distintas de
  /// [detection]. Recorre cada unión una vez.
  factory CommunityLinks.of(
    TopicAdjacency adjacency,
    CommunityDetection detection,
  ) {
    final ids = [for (final c in detection.communities) c.id];
    final denseOf = {for (var c = 0; c < ids.length; c++) ids[c]: c};
    final n = adjacency.nodeCount;
    final communityOfTopic = Int32List(n);
    for (var i = 0; i < n; i++) {
      communityOfTopic[i] = denseOf[detection.communityOf[i]]!;
    }

    final weight = HashMap<int, double>();
    final count = HashMap<int, int>();
    final c = ids.length;
    var visits = 0;
    for (var i = 0; i < n; i++) {
      for (var e = adjacency.offsets[i]; e < adjacency.offsets[i + 1]; e++) {
        visits++;
        final j = adjacency.neighbors[e];
        // Cada unión está en las listas de sus dos temas: se cuenta desde el
        // de menor posición.
        if (j <= i) continue;
        final a = communityOfTopic[i];
        final b = communityOfTopic[j];
        if (a == b) continue;
        final key = a < b ? a * c + b : b * c + a;
        weight[key] = (weight[key] ?? 0) + adjacency.weights[e];
        count[key] = (count[key] ?? 0) + 1;
      }
    }

    final neighbors = List.generate(c, (_) => <CommunityLink>[]);
    for (final MapEntry(key: key, value: w) in weight.entries) {
      final a = key ~/ c;
      final b = key % c;
      neighbors[a].add(CommunityLink(communityId: ids[b], weight: w));
      neighbors[b].add(CommunityLink(communityId: ids[a], weight: w));
    }
    for (final list in neighbors) {
      list.sort((x, y) {
        final byWeight = y.weight.compareTo(x.weight);
        return byWeight != 0
            ? byWeight
            : denseOf[x.communityId]!.compareTo(denseOf[y.communityId]!);
      });
    }

    return CommunityLinks._(
      denseOf: denseOf,
      ids: ids,
      communityOfTopic: communityOfTopic,
      weight: weight,
      count: count,
      neighbors: neighbors,
      visits: visits,
    );
  }

  /// La posición de cada comunidad en [ids], por su identidad.
  final Map<int, int> denseOf;

  /// Las identidades de las comunidades, en el orden de
  /// `CommunityDetection.communities`.
  final List<int> ids;

  /// La posición en [ids] de la comunidad de cada tema.
  final Int32List communityOfTopic;

  final HashMap<int, double> _weight;
  final HashMap<int, int> _count;
  final List<List<CommunityLink>> _neighbors;

  /// Cuántas entradas de las uniones se miraron: el doble de las uniones.
  final int visits;

  int _key(int a, int b) => a < b ? a * ids.length + b : b * ids.length + a;

  /// Lo que suman las uniones entre las comunidades en las posiciones [a] y
  /// [b] de [ids].
  double weightBetween(int a, int b) => _weight[_key(a, b)] ?? 0;

  /// Cuántas uniones hay entre las comunidades en las posiciones [a] y [b].
  int countBetween(int a, int b) => _count[_key(a, b)] ?? 0;

  /// Las comunidades que más se unen con la de identidad [communityId], como
  /// mucho [limit].
  List<CommunityLink> neighborsOf(
    int communityId, {
    int limit = kCommunityNeighbors,
  }) {
    final at = denseOf[communityId];
    if (at == null) return const [];
    final all = _neighbors[at];
    return all.length <= limit ? all : all.sublist(0, limit);
  }
}
