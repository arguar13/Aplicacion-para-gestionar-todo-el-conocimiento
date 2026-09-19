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

/// Qué parte del grafo corresponde ver, según el espacio elegido y cuántos
/// saltos más allá de él se quieren revelar.
///
/// `spaceId == null` es "todos los espacios": no hay nada que recortar, y
/// [edges] vuelve tal cual —salvo las aristas que apuntan a un elemento que
/// ya no existe—. Con un espacio elegido, arranca desde los elementos de ese
/// espacio y expande salto a salto por los vínculos: `degree == 0` muestra
/// solo lo que conecta puertas adentro del espacio, `degree == 1` suma
/// además los vínculos directos hacia afuera, y así — `degree == null` no
/// pone techo, y expande hasta el borde de cada red conectada que toque el
/// espacio.
///
/// Función pura y determinística a propósito, igual que
/// `computeGraphLayout`: lo único que puede salir mal acá es la lógica de
/// selección, y eso se prueba sin montar ninguna pantalla.
({List<String> nodeIds, List<RelationEdge> edges}) scopeGraph({
  required List<KnowledgeItem> items,
  required List<RelationEdge> edges,
  required String? spaceId,
  int? degree,
}) {
  final validEdges = _validEdges(items, edges);

  if (spaceId == null) {
    final nodeIds = <String>{
      for (final edge in validEdges) ...[edge.fromItemId, edge.toItemId],
    }.toList();
    return (nodeIds: nodeIds, edges: validEdges);
  }

  final seed = <String>{
    for (final item in items)
      if (item.spaceId == spaceId) item.id,
  };

  return _expandFromSeed(seed: seed, validEdges: validEdges, degree: degree);
}

/// El vecindario de UN elemento —el semilla— hasta [degree] saltos, para
/// el grafo local (ver la decisión sobre F6): mismo BFS que [scopeGraph]
/// usa para expandir más allá de un espacio, pero arrancando de un solo
/// ítem en vez de todos los que comparten un `spaceId`.
///
/// `degree` con default `1` —a diferencia de [scopeGraph], que no pone
/// techo por defecto—: un panel embebido en un detalle tiene que mostrar
/// los vecinos directos, no la red entera alcanzable desde ahí. Si
/// [seedItemId] no está entre [items], o no tiene ningún vínculo, el
/// resultado es vacío, no un nodo suelto —mismo criterio que el resto del
/// grafo (decisión 19)—.
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

/// El BFS compartido por [scopeGraph] (semilla = un espacio) y
/// [localGraphFrom] (semilla = un solo ítem): expande [seed] salto a
/// salto por [validEdges], hasta [degree] saltos o sin techo si es
/// `null`, y recorta las aristas al conjunto ya visitado.
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

/// Parte los nodos de un grafo en sus componentes conexas: grupos de
/// elementos que se pueden alcanzar unos a otros siguiendo vínculos, sin
/// pasar por ningún elemento de fuera del grupo.
///
/// Es la base de "un grafo por tema" sin pedirle a nadie que clasifique
/// nada a mano: dos elementos vinculados ya están, por definición,
/// relacionados —es la razón por la que alguien puso el vínculo—, así que
/// agruparlos por hasta dónde se puede llegar de uno a otro es agrupar por
/// tema con la información que ya existe, en vez de sumar una clasificación
/// nueva que alguien tendría que mantener a mano.
///
/// De paso resuelve el otro problema de mirar el grafo entero de una vez:
/// el layout de `computeGraphLayout` repele todos los pares de nodos por
/// igual, conectados o no, así que dos grupos sin ningún vínculo entre
/// ellos terminan empujándose a los extremos de un lienzo que crece con la
/// cantidad total de nodos — cuantos más temas sueltos haya, más disperso
/// y más difícil de ver entero queda cada uno. Mostrar un componente a la
/// vez es mostrar solo lo que de verdad se repele y se atrae entre sí.
///
/// Se devuelven ordenados de mayor a menor cantidad de nodos: el primero es
/// casi siempre el que interesa mirar primero.
List<Set<String>> computeConnectedComponents({
  required List<String> nodeIds,
  required List<RelationEdge> edges,
}) {
  final adjacency = <String, List<String>>{};
  for (final edge in edges) {
    adjacency.putIfAbsent(edge.fromItemId, () => []).add(edge.toItemId);
    adjacency.putIfAbsent(edge.toItemId, () => []).add(edge.fromItemId);
  }

  final remaining = nodeIds.toSet();
  final components = <Set<String>>[];

  for (final start in nodeIds) {
    if (!remaining.contains(start)) continue;

    final component = <String>{};
    final pending = <String>[start];
    remaining.remove(start);

    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      component.add(current);
      for (final neighbor in adjacency[current] ?? const <String>[]) {
        if (remaining.remove(neighbor)) pending.add(neighbor);
      }
    }
    components.add(component);
  }

  // Estable a propósito: `List.sort` en Dart lo es, así que dos componentes
  // del mismo tamaño mantienen el orden en que aparecieron sus nodos en
  // `nodeIds` — nada de que el resultado "salte" entre corridas con los
  // mismos datos de entrada.
  components.sort((a, b) => b.length.compareTo(a.length));
  return components;
}
