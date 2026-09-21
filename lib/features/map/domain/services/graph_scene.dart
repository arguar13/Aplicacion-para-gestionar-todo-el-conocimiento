import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/map_layout.dart';

/// Qué es un nodo de lo que se dibuja en el grafo de conocimiento.
enum SceneKind {
  /// Una comunidad de temas.
  community,

  /// Varias comunidades chicas juntas.
  overflow,

  /// Los temas sin ninguna unión, juntos.
  isolated,

  /// Un tema.
  topic,

  /// Una nota.
  note,

  /// Una fuente.
  source,
}

/// Un nodo de lo que se dibuja: sin posición todavía.
class SceneNode {
  const SceneNode({
    required this.key,
    required this.kind,
    required this.label,
    required this.size,
    this.group,
    this.count = 0,
    this.ref,
  });

  /// Único en la escena: `overview:3`, `topic:roma`, `item:i1`.
  final String key;
  final SceneKind kind;

  /// El nombre; vacío en los nodos que juntan varios (los rotula la pantalla).
  final String label;

  /// Cuánto pesa: los elementos que tiene, para dibujarlo más grande o más
  /// chico.
  final int size;

  /// La identidad de la comunidad a la que pertenece —para colorearlo— o `null`
  /// si no tiene una.
  final int? group;

  /// Cuántos temas junta, en un nodo de comunidad.
  final int count;

  /// A qué apunta: el valor de un tema o el elemento; `null` en una comunidad.
  final String? ref;
}

/// Una unión entre dos nodos de la escena.
class SceneEdge {
  const SceneEdge({
    required this.a,
    required this.b,
    required this.weight,
    this.tension = false,
    this.relation,
  });

  /// Posiciones en `GraphScene.nodes`.
  final int a;
  final int b;
  final double weight;

  /// Si es una contradicción, o junta alguna.
  final bool tension;

  /// El tipo de vínculo, en el nivel de los elementos; `null` entre temas.
  final RelationKind? relation;
}

/// Lo que se dibuja en un nivel del grafo de conocimiento: nodos y uniones, más
/// lo que hace falta para acomodarlos.
class GraphScene {
  const GraphScene({required this.nodes, required this.edges, this.hidden = 0});

  const GraphScene.empty() : nodes = const [], edges = const [], hidden = 0;

  final List<SceneNode> nodes;
  final List<SceneEdge> edges;

  /// Cuántos nodos quedaron sin dibujar por el tope del nivel.
  final int hidden;

  int? indexOf(String key) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].key == key) return i;
    }
    return null;
  }

  /// Las uniones para el layout de fuerzas.
  List<MapLayoutLink> get links => [
    for (final edge in edges) MapLayoutLink(edge.a, edge.b, edge.weight),
  ];
}

/// El nivel alejado: cada comunidad, o grupo de ellas, es un nodo.
GraphScene sceneOfOverview(TopicGraph graph, CommunityOverview overview) {
  return GraphScene(
    nodes: [
      for (var i = 0; i < overview.nodes.length; i++)
        _overviewNode(graph, overview.nodes[i], i),
    ],
    edges: [
      for (final edge in overview.edges)
        SceneEdge(
          a: edge.a,
          b: edge.b,
          weight: edge.weight,
          tension: edge.hasTension,
        ),
    ],
  );
}

SceneNode _overviewNode(TopicGraph graph, OverviewNode node, int index) {
  final anchor = node.anchor;
  return SceneNode(
    key: 'overview:$index',
    kind: switch (node.kind) {
      OverviewKind.community => SceneKind.community,
      OverviewKind.overflow => SceneKind.overflow,
      OverviewKind.isolated => SceneKind.isolated,
    },
    label: anchor == null ? '' : graph.nodes[anchor].label,
    size: node.itemCount,
    group: node.kind == OverviewKind.community ? node.communityIds.first : null,
    count: node.topicCount,
  );
}

/// El nivel medio: los temas elegidos, coloreados por su comunidad.
GraphScene sceneOfTopics(
  TopicGraph graph,
  CommunityDetection detection,
  TopicSelection selection, {
  TopicGraphWeights weights = const TopicGraphWeights(),
}) {
  final position = {
    for (var i = 0; i < selection.topics.length; i++) selection.topics[i]: i,
  };
  return GraphScene(
    nodes: [
      for (final topic in selection.topics)
        SceneNode(
          key: 'topic:${graph.nodes[topic].valueId}',
          kind: SceneKind.topic,
          label: graph.nodes[topic].label,
          size: graph.nodes[topic].itemCount,
          group: detection.communityOf[topic],
          ref: graph.nodes[topic].valueId,
        ),
    ],
    edges: [
      for (final e in selection.edges)
        SceneEdge(
          a: position[graph.edges[e].a]!,
          b: position[graph.edges[e].b]!,
          weight: weights.of(graph.edges[e]),
          tension: graph.edges[e].isTension,
        ),
    ],
    hidden: selection.hidden,
  );
}

/// El nivel cercano: los elementos de un tema y los vínculos entre ellos.
GraphScene sceneOfItems(TopicItemsGraph items) {
  return GraphScene(
    nodes: [
      for (final item in items.items)
        SceneNode(
          key: 'item:${item.id}',
          kind: item.isNote ? SceneKind.note : SceneKind.source,
          label: item.title,
          size: 1,
          ref: item.id,
        ),
    ],
    edges: [
      for (final edge in items.edges)
        SceneEdge(
          a: edge.a,
          b: edge.b,
          // Una contradicción une más que una cita, como entre temas.
          weight: edge.kind == RelationKind.contradicts ? 3 : 2,
          tension: edge.kind == RelationKind.contradicts,
          relation: edge.kind,
        ),
    ],
    hidden: items.truncated ? 1 : 0,
  );
}
