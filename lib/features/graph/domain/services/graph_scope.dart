import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_edge.dart';

/// Cuántos elementos dibuja, como mucho, el panel del detalle: es una vista
/// previa de doscientos píxeles de alto y más nodos que estos no caben ni se
/// leen. Lo que sobra lo dice el propio panel; la pantalla completa lo muestra.
const kLocalGraphPanelMaxNodes = 30;

/// Cuántos dibuja, como mucho, la pantalla del grafo local. Un elemento muy
/// conectado puede tener miles de vecinos, y el layout de fuerzas es cuadrático
/// en la cantidad de nodos: pasado este tope, más nodos dejan de ser una vista
/// y son una espera.
const kLocalGraphScreenMaxNodes = 200;

/// El vecindario de UN elemento —el semilla— hasta [degree] saltos, para
/// el grafo local (ver la decisión sobre F6): expande salto a salto por los
/// vínculos, arrancando de un solo ítem.
///
/// `degree` con default `1`: un panel embebido en un detalle tiene que
/// mostrar los vecinos directos, no la red entera alcanzable desde ahí; con
/// `null` no hay techo. Si [seedItemId] no está entre [items], o no tiene
/// ningún vínculo, el resultado es vacío, no un nodo suelto —mismo criterio
/// que el resto del grafo (decisión 19)—.
({List<String> nodeIds, List<RelationEdge> edges}) localGraphFrom({
  required String seedItemId,
  required List<KnowledgeItem> items,
  required List<RelationEdge> edges,
  int? degree = 1,
}) {
  final validEdges = _validEdges(items, edges);
  return _expandFromSeed(
    seed: {seedItemId},
    validEdges: validEdges,
    degree: degree,
  );
}

/// Las aristas cuyos dos extremos siguen existiendo entre [items]: el
/// otro extremo de una arista puede apuntar a un elemento que ya no
/// existe, porque las aristas y los elementos vienen de streams
/// separados que no se actualizan en el mismo instante.
List<RelationEdge> _validEdges(
  List<KnowledgeItem> items,
  List<RelationEdge> edges,
) {
  final itemsById = {for (final item in items) item.id: item};
  return edges
      .where(
        (edge) =>
            itemsById.containsKey(edge.fromItemId) &&
            itemsById.containsKey(edge.toItemId),
      )
      .toList();
}

/// El BFS de [localGraphFrom]: expande [seed] salto a salto por
/// [validEdges], hasta [degree] saltos o sin techo si es `null`, y recorta
/// las aristas al conjunto ya visitado.
({List<String> nodeIds, List<RelationEdge> edges}) _expandFromSeed({
  required Set<String> seed,
  required List<RelationEdge> validEdges,
  int? degree,
}) {
  final adjacency = <String, List<RelationEdge>>{};
  for (final edge in validEdges) {
    adjacency.putIfAbsent(edge.fromItemId, () => []).add(edge);
    adjacency.putIfAbsent(edge.toItemId, () => []).add(edge);
  }

  var visited = seed;
  var frontier = visited;
  var hop = 0;

  while (frontier.isNotEmpty && (degree == null || hop < degree)) {
    final next = <String>{};
    for (final id in frontier) {
      for (final edge in adjacency[id] ?? const <RelationEdge>[]) {
        final other = edge.fromItemId == id ? edge.toItemId : edge.fromItemId;
        if (!visited.contains(other)) next.add(other);
      }
    }
    if (next.isEmpty) break;

    visited = {...visited, ...next};
    frontier = next;
    hop++;
  }

  final scopedEdges = validEdges
      .where(
        (edge) =>
            visited.contains(edge.fromItemId) &&
            visited.contains(edge.toItemId),
      )
      .toList();
  final nodeIds = <String>{
    for (final edge in scopedEdges) ...[edge.fromItemId, edge.toItemId],
  }.toList();

  return (nodeIds: nodeIds, edges: scopedEdges);
}
