import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Las uniones de un grafo de temas en forma de listas por tema: `neighbors` y
/// `weights` desde `offsets[i]` hasta `offsets[i + 1]` son las del tema `i`.
/// Una unión aparece en las listas de sus dos temas.
///
/// Es lo que recorren las comunidades y lo que el motor sabe además de ellas
/// —los puentes, el nombre de cada comunidad (F44)—: se arma UNA vez por
/// cálculo y lo comparten, así que todos miden la misma cosa con el mismo peso.
///
/// Solo lleva listas de números: cruza sin problema al isolate del cálculo.
class TopicAdjacency {
  TopicAdjacency._(this.offsets, this.neighbors, this.weights);

  /// Las uniones de [graph], cada una con lo que pesa según [weights], más la
  /// de cada tema con su padre de la jerarquía, que pesa [hierarchyWeight].
  /// Una unión que no pesa nada no se cuenta.
  factory TopicAdjacency.of(
    TopicGraph graph,
    TopicGraphWeights weights,
    double hierarchyWeight,
  ) {
    final n = graph.nodes.length;
    final a = <int>[];
    final b = <int>[];
    final w = <double>[];
    for (final edge in graph.edges) {
      final weight = weights.of(edge);
      if (weight <= 0) continue;
      a.add(edge.a);
      b.add(edge.b);
      w.add(weight);
    }
    if (hierarchyWeight > 0) {
      for (var i = 0; i < n; i++) {
        final parentId = graph.nodes[i].parentId;
        final parent = parentId == null ? null : graph.indexOf(parentId);
        if (parent == null || parent == i) continue;
        a.add(i);
        b.add(parent);
        w.add(hierarchyWeight);
      }
    }

    final offsets = Int32List(n + 1);
    for (var k = 0; k < a.length; k++) {
      offsets[a[k] + 1]++;
      offsets[b[k] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      offsets[i + 1] += offsets[i];
    }
    final neighbors = Int32List(offsets[n]);
    final edgeWeights = Float64List(offsets[n]);
    final cursor = Int32List.fromList(offsets);
    for (var k = 0; k < a.length; k++) {
      neighbors[cursor[a[k]]] = b[k];
      edgeWeights[cursor[a[k]]++] = w[k];
      neighbors[cursor[b[k]]] = a[k];
      edgeWeights[cursor[b[k]]++] = w[k];
    }
    return TopicAdjacency._(offsets, neighbors, edgeWeights);
  }

  final Int32List offsets;
  final Int32List neighbors;
  final Float64List weights;

  /// Cuántos temas tiene el grafo del que salió.
  int get nodeCount => offsets.length - 1;

  int degreeOf(int i) => offsets[i + 1] - offsets[i];

  /// Lo que suman las uniones del tema [i].
  double weightOf(int i) {
    var total = 0.0;
    for (var e = offsets[i]; e < offsets[i + 1]; e++) {
      total += weights[e];
    }
    return total;
  }
}
