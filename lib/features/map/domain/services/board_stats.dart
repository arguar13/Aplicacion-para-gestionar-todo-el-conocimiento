import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Cuántas filas trae cada lista del tablero.
const kBoardListLength = 8;

/// Un par de temas unidos, con lo que pesa la unión.
class ConnectedPair {
  const ConnectedPair({
    required this.first,
    required this.second,
    required this.edge,
    required this.weight,
  });

  final TopicNode first;
  final TopicNode second;
  final TopicEdge edge;
  final double weight;
}

/// Lo que el tablero del mapa (F14) saca del grafo de temas.
class BoardStats {
  const BoardStats({
    required this.topicCount,
    required this.communityCount,
    required this.densest,
    required this.connected,
    required this.isolated,
    required this.isolatedCount,
  });

  final int topicCount;

  /// Cuántas comunidades con uniones hay: los temas aislados no cuentan como
  /// comunidades.
  final int communityCount;

  /// Los temas con más elementos asignados directamente, de más a menos.
  final List<TopicNode> densest;

  /// Los pares de temas más unidos, de más a menos.
  final List<ConnectedPair> connected;

  /// Los primeros temas sin ninguna unión, los de más elementos primero.
  final List<TopicNode> isolated;

  /// Cuántos temas hay sin ninguna unión, en total.
  final int isolatedCount;
}

/// Calcula lo que muestra el tablero: los temas más densos, los pares más
/// conectados y los aislados.
///
/// Sin empates que dependan del orden en que llegaron los datos: a igual
/// cantidad, manda la posición del tema, que es por nombre.
BoardStats boardStatsOf(
  TopicGraph graph,
  CommunityDetection detection, {
  TopicGraphWeights weights = const TopicGraphWeights(),
  int limit = kBoardListLength,
}) {
  final nodes = graph.nodes;

  final densest =
      [
        for (var i = 0; i < nodes.length; i++)
          if (nodes[i].itemCount > 0) i,
      ]..sort((x, y) {
        final byItems = nodes[y].itemCount.compareTo(nodes[x].itemCount);
        return byItems != 0 ? byItems : x.compareTo(y);
      });

  final connected =
      <(int, double)>[
        for (var e = 0; e < graph.edges.length; e++)
          (e, weights.of(graph.edges[e])),
      ]..sort((x, y) {
        final byWeight = y.$2.compareTo(x.$2);
        return byWeight != 0 ? byWeight : x.$1.compareTo(y.$1);
      });

  final joined = Uint8List(nodes.length);
  for (final edge in graph.edges) {
    joined[edge.a] = 1;
    joined[edge.b] = 1;
  }
  final isolated =
      [
        for (var i = 0; i < nodes.length; i++)
          if (joined[i] == 0) i,
      ]..sort((x, y) {
        final byItems = nodes[y].itemCount.compareTo(nodes[x].itemCount);
        return byItems != 0 ? byItems : x.compareTo(y);
      });

  return BoardStats(
    topicCount: nodes.length,
    communityCount: detection.communities.where((c) => !c.isIsolated).length,
    densest: [for (final i in densest.take(limit)) nodes[i]],
    connected: [
      for (final (e, weight) in connected.take(limit))
        ConnectedPair(
          first: nodes[graph.edges[e].a],
          second: nodes[graph.edges[e].b],
          edge: graph.edges[e],
          weight: weight,
        ),
    ],
    isolated: [for (final i in isolated.take(limit)) nodes[i]],
    isolatedCount: isolated.length,
  );
}
