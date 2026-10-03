import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
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
  const GraphScene({
    required this.nodes,
    required this.edges,
    this.hidden = 0,
    this.hiddenEdges = 0,
  });

  const GraphScene.empty()
    : nodes = const [],
      edges = const [],
      hidden = 0,
      hiddenEdges = 0;

  final List<SceneNode> nodes;
  final List<SceneEdge> edges;

  /// Cuántos nodos quedaron sin dibujar por el tope del nivel.
  final int hidden;

  /// Cuántas uniones quedaron sin dibujar porque no eran de las más fuertes de
  /// ninguno de sus dos extremos: ver [strongestEdges].
  final int hiddenEdges;

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

/// Cuántas uniones conserva, como mucho, cada tema en el nivel de temas.
const kTopicEdgesPerNode = 4;

/// Las uniones que valen la pena dibujar: cada nodo conserva las [perNode] más
/// fuertes de las suyas, y una unión sobrevive si es de las más fuertes de
/// alguno de sus dos extremos. Las contradicciones se conservan siempre: son lo
/// que el mapa tiene que señalar.
///
/// Entre trescientos temas hay miles de uniones —los que comparten algún
/// elemento—, y dibujarlas todas no se lee: es una maraña, y es lo que más
/// cuesta de dibujar en cada cuadro de un gesto —más que los trescientos nodos
/// con sus etiquetas juntos—. Con las más fuertes de cada uno queda la
/// estructura. Es determinista: a igual fuerza, gana la que venía antes.
///
/// Devuelve las uniones en su orden original, y a lo sumo `perNode` por nodo
/// más las contradicciones.
List<SceneEdge> strongestEdges(
  List<SceneEdge> edges,
  int nodeCount, {
  int perNode = kTopicEdgesPerNode,
}) {
  final incident = List.generate(nodeCount, (_) => <int>[]);
  for (var i = 0; i < edges.length; i++) {
    incident[edges[i].a].add(i);
    incident[edges[i].b].add(i);
  }
  final keep = [for (final edge in edges) edge.tension];
  for (final list in incident) {
    if (list.length <= perNode) {
      for (final i in list) {
        keep[i] = true;
      }
      continue;
    }
    list.sort((x, y) {
      final byWeight = edges[y].weight.compareTo(edges[x].weight);
      return byWeight != 0 ? byWeight : x.compareTo(y);
    });
    for (final i in list.take(perNode)) {
      keep[i] = true;
    }
  }
  return [
    for (var i = 0; i < edges.length; i++)
      if (keep[i]) edges[i],
  ];
}

/// El nivel medio: los temas elegidos, coloreados por su comunidad, unidos por
/// lo que los une y por la jerarquía: un subtema se pega a su padre con el peso
/// de un elemento compartido (`kHierarchyWeight`), como en las comunidades.
GraphScene sceneOfTopics(
  TopicGraph graph,
  CommunityDetection detection,
  TopicSelection selection, {
  TopicGraphWeights weights = const TopicGraphWeights(),
}) {
  final position = {
    for (var i = 0; i < selection.topics.length; i++) selection.topics[i]: i,
  };

  // Las uniones, una por par: si un subtema ya está unido a su padre por algo,
  // la jerarquía suma a esa unión.
  final at = <int, int>{};
  final edges = <SceneEdge>[];
  void join(int a, int b, double weight, {required bool tension}) {
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    final key = low * selection.topics.length + high;
    final existing = at[key];
    if (existing == null) {
      at[key] = edges.length;
      edges.add(SceneEdge(a: low, b: high, weight: weight, tension: tension));
    } else {
      final before = edges[existing];
      edges[existing] = SceneEdge(
        a: before.a,
        b: before.b,
        weight: before.weight + weight,
        tension: before.tension || tension,
      );
    }
  }

  for (final e in selection.edges) {
    join(
      position[graph.edges[e].a]!,
      position[graph.edges[e].b]!,
      weights.of(graph.edges[e]),
      tension: graph.edges[e].isTension,
    );
  }
  for (final topic in selection.topics) {
    final parentId = graph.nodes[topic].parentId;
    final parent = parentId == null ? null : graph.indexOf(parentId);
    final parentAt = parent == null ? null : position[parent];
    if (parentAt != null) {
      join(position[topic]!, parentAt, kHierarchyWeight, tension: false);
    }
  }

  final drawn = strongestEdges(edges, selection.topics.length);
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
    edges: drawn,
    hidden: selection.hidden,
    hiddenEdges: edges.length - drawn.length,
  );
}

/// El nivel cercano: los elementos de un tema y los vínculos entre ellos.
GraphScene sceneOfItems(TopicItemsGraph items) {
  return GraphScene(
    nodes: [for (final item in items.items) _itemNode(item)],
    edges: [for (final edge in items.edges) _itemEdge(edge)],
    hidden: items.truncated ? 1 : 0,
  );
}

/// La vista «Vínculos» (F28): los elementos vinculados, sin temas de por
/// medio, con el mismo dibujo que el nivel de elementos.
///
/// Cada grupo de elementos unidos entre sí —una componente conexa— es un
/// grupo para el layout: lo que está vinculado queda junto, y dos grupos
/// sueltos no se mezclan.
GraphScene sceneOfLinks(LinkGraph graph) {
  final count = graph.items.length;
  // Las componentes, con una unión por rango: cada elemento apunta a uno de su
  // grupo, y el de más arriba es el que lo nombra.
  final parent = List<int>.generate(count, (i) => i);
  int root(int i) {
    var node = i;
    while (parent[node] != node) {
      parent[node] = parent[parent[node]];
      node = parent[node];
    }
    return node;
  }

  for (final edge in graph.edges) {
    final a = root(edge.a);
    final b = root(edge.b);
    if (a != b) parent[a < b ? b : a] = a < b ? a : b;
  }

  return GraphScene(
    nodes: [
      for (var i = 0; i < count; i++) _itemNode(graph.items[i], group: root(i)),
    ],
    edges: [for (final edge in graph.edges) _itemEdge(edge)],
    hidden: graph.hidden,
  );
}

SceneNode _itemNode(TopicItemNode item, {int? group}) => SceneNode(
  key: 'item:${item.id}',
  kind: item.isNote ? SceneKind.note : SceneKind.source,
  label: item.title,
  size: 1,
  group: group,
  ref: item.id,
);

SceneEdge _itemEdge(TopicItemEdge edge) => SceneEdge(
  a: edge.a,
  b: edge.b,
  // Una contradicción une más que una cita, como entre temas.
  weight: edge.kind == RelationKind.contradicts ? 3 : 2,
  tension: edge.kind == RelationKind.contradicts,
  relation: edge.kind,
);
