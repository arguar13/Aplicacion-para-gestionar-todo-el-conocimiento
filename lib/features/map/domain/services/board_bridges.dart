import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_stats.dart';

/// Un tema puente del Resumen (F44, paso 3): uno que une comunidades
/// distintas, o que, si se sacara, dejaría partes sueltas. Son los que mejor
/// ordenan lo que se sabe: por ellos pasa lo que conecta una cosa con otra.
class BoardBridge {
  const BoardBridge({
    required this.topic,
    required this.joins,
    required this.crossWeight,
    required this.parts,
  });

  final TopicNode topic;

  /// Las OTRAS comunidades con las que se une —no la suya—, la más unida
  /// primero. Vacía si es puente solo por [parts].
  final List<TopicCommunity> joins;

  /// Cuánto pesan, sumadas, sus uniones con temas de otras comunidades.
  final double crossWeight;

  /// En cuántas partes quedaría lo que lo rodea si se lo sacara: 0 si no es
  /// un punto de corte —sacarlo no separa nada—; si lo es, 2 o más.
  final int parts;
}

/// Los temas puente de [graph], del que más une al que menos: primero los que
/// tocan más comunidades, después los que más partes dejarían sueltas, después
/// los de uniones más pesadas, y a igual todo, por posición (que es por
/// nombre). A lo sumo [limit].
///
/// Es un cálculo lineal en temas y uniones, sin nada que crezca con el
/// cuadrado: las comunidades que toca cada tema salen de recorrer sus uniones
/// una vez, y los puntos de corte, de un recorrido en profundidad (Tarjan)
/// hecho con una pila propia, para que un grafo largo no agote la del hilo.
///
/// Lo calcula el Resumen mientras el motor del Mapa no lo entregue hecho (F44,
/// paso 1): la firma es la de un derivado del mapa, para que cambiarlo por el
/// del motor sea cambiar quién llama.
List<BoardBridge> bridgesOf(
  TopicGraph graph,
  CommunityDetection detection, {
  TopicGraphWeights weights = const TopicGraphWeights(),
  int limit = kBoardListLength,
}) {
  final n = graph.nodes.length;
  if (n == 0 || graph.edges.isEmpty) return const [];
  final communityOf = detection.communityOf;

  // Lo que cada tema pesa hacia cada comunidad ajena.
  final foreign = List<Map<int, double>?>.filled(n, null);
  void touch(int from, int to, double weight) {
    final own = communityOf[from];
    final other = communityOf[to];
    if (own == other) return;
    (foreign[from] ??= <int, double>{}).update(
      other,
      (w) => w + weight,
      ifAbsent: () => weight,
    );
  }

  for (final edge in graph.edges) {
    final weight = weights.of(edge);
    touch(edge.a, edge.b, weight);
    touch(edge.b, edge.a, weight);
  }

  final parts = _cutParts(n, graph.edges);

  final candidates = <int>[
    for (var i = 0; i < n; i++)
      if (foreign[i] != null || parts[i] >= 2) i,
  ];
  double crossOf(int i) =>
      foreign[i]?.values.fold<double>(0, (sum, w) => sum + w) ?? 0;
  final cross = {for (final i in candidates) i: crossOf(i)};

  candidates.sort((x, y) {
    final byJoins = (foreign[y]?.length ?? 0).compareTo(
      foreign[x]?.length ?? 0,
    );
    if (byJoins != 0) return byJoins;
    final byParts = parts[y].compareTo(parts[x]);
    if (byParts != 0) return byParts;
    final byWeight = cross[y]!.compareTo(cross[x]!);
    return byWeight != 0 ? byWeight : x.compareTo(y);
  });

  return [
    for (final i in candidates.take(limit))
      BoardBridge(
        topic: graph.nodes[i],
        joins: _joinsOf(foreign[i], detection),
        crossWeight: cross[i]!,
        parts: parts[i],
      ),
  ];
}

/// Las comunidades de [weights], de la más unida a la menos; a igual peso, por
/// identidad.
List<TopicCommunity> _joinsOf(
  Map<int, double>? weights,
  CommunityDetection detection,
) {
  if (weights == null) return const [];
  final ids = weights.keys.toList()
    ..sort((x, y) {
      final byWeight = weights[y]!.compareTo(weights[x]!);
      return byWeight != 0 ? byWeight : x.compareTo(y);
    });
  return [
    for (final id in ids)
      if (detection.communityById(id) case final community?) community,
  ];
}

/// En cuántas partes quedaría el vecindario de cada tema si se lo sacara: 0
/// si no es un punto de corte.
///
/// Tarjan sobre el grafo no dirigido, con las adyacencias en dos arreglos
/// planos (CSR) y una pila explícita. Un tema que no es la raíz de su
/// recorrido corta cuando algún hijo no tiene cómo volver por encima de él
/// (`low[hijo] >= disc[tema]`): cada uno de esos hijos es una parte, y lo de
/// arriba, otra. La raíz corta si tiene dos hijos o más, y cada uno es una
/// parte.
Int32List _cutParts(int n, List<TopicEdge> edges) {
  final degree = Int32List(n + 1);
  for (final edge in edges) {
    degree[edge.a + 1]++;
    degree[edge.b + 1]++;
  }
  for (var i = 0; i < n; i++) {
    degree[i + 1] += degree[i];
  }
  final start = Int32List.fromList(degree);
  final fill = Int32List.fromList(degree);
  final adjacent = Int32List(edges.length * 2);
  for (final edge in edges) {
    adjacent[fill[edge.a]++] = edge.b;
    adjacent[fill[edge.b]++] = edge.a;
  }

  final disc = Int32List(n)..fillRange(0, n, -1);
  final low = Int32List(n);
  final parent = Int32List(n)..fillRange(0, n, -1);
  final next = Int32List(n);
  final splits = Int32List(n);
  final parts = Int32List(n);
  final stack = Int32List(n);
  var time = 0;

  for (var root = 0; root < n; root++) {
    if (disc[root] != -1) continue;
    var top = 0;
    stack[top++] = root;
    disc[root] = low[root] = time++;
    next[root] = start[root];
    var rootChildren = 0;

    while (top > 0) {
      final u = stack[top - 1];
      if (next[u] < start[u + 1]) {
        final v = adjacent[next[u]++];
        if (disc[v] == -1) {
          parent[v] = u;
          disc[v] = low[v] = time++;
          next[v] = start[v];
          stack[top++] = v;
          if (u == root) rootChildren++;
        } else if (v != parent[u] && disc[v] < low[u]) {
          low[u] = disc[v];
        }
        continue;
      }
      // [u] terminó: lo que alcanza se lo pasa a su padre.
      top--;
      final p = parent[u];
      if (p == -1) continue;
      if (low[u] < low[p]) low[p] = low[u];
      if (p != root && low[u] >= disc[p]) splits[p]++;
    }

    if (rootChildren >= 2) parts[root] = rootChildren;
  }
  for (var i = 0; i < n; i++) {
    if (splits[i] > 0) parts[i] = splits[i] + 1;
  }
  return parts;
}
