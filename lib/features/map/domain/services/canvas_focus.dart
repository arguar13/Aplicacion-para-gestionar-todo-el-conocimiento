import 'package:sinapsis/features/map/domain/services/graph_scene.dart';

/// El vecindario de [center] en el modo foco del lienzo (F44, paso 4,
/// «Centrar aquí»): sus posiciones en `scene.nodes`, con él, y las de los
/// nodos a [degree] saltos o menos por las uniones que se dibujan.
///
/// [degree] es el «Grado»: 0, solo él; 1, también los unidos directamente; 2,
/// también los unidos a esos; `null`, todo lo que se alcanza. Lo que queda
/// afuera, el lienzo lo apaga.
///
/// Va por anillos y mira cada unión una vez por anillo: lineal en lo que se
/// dibuja, que ya está topeado (60 comunidades, 300 temas o 200 documentos).
/// No toca el grafo ni la base: centrar no recalcula nada. Un [center] que no
/// está en [scene] no tiene vecindario.
Set<int> focusNeighborhood(GraphScene scene, int center, {int? degree = 1}) {
  final count = scene.nodes.length;
  if (center < 0 || center >= count) return const {};
  final neighbors = List.generate(count, (_) => <int>[]);
  for (final edge in scene.edges) {
    if (edge.a == edge.b) continue;
    neighbors[edge.a].add(edge.b);
    neighbors[edge.b].add(edge.a);
  }

  final reached = {center};
  var ring = [center];
  for (var hop = 1; degree == null || hop <= degree; hop++) {
    final next = <int>[];
    for (final node in ring) {
      for (final other in neighbors[node]) {
        if (reached.add(other)) next.add(other);
      }
    }
    if (next.isEmpty) break;
    ring = next;
  }
  return reached;
}
