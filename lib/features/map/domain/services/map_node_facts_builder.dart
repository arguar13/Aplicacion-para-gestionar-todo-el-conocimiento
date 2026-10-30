import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/map_insights.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';

/// Cuántos vecinos nombra la ficha en «Une con».
const kMapNodeNeighbors = 3;

/// Cuántos temas de una comunidad nombra la ficha; los demás se cuentan.
const kMapNodeTopicNames = 8;

/// Lo que dice la ficha de [ref] (F44, paso 4), con lo que el lienzo ya tiene:
/// el grafo de temas y sus comunidades —[overview], lo que se ve de lejos—, lo
/// que el motor sabe ([insights]) y lo que se dibuja: la red ([scene]) y, en
/// Radial, Árbol o la lista, el árbol ([tree]). `null` si [ref] no está en
/// ninguno: un tema que ya no existe, un documento que no se ve ni está en el
/// mapa.
///
/// - **Una comunidad**: su nombre, sus temas, sus documentos y vínculos, con
///   qué comunidades se une más y lo más reciente, de `insights.communities`.
///   Sin eso —un mapa calculado sin `insights`—, su tema más unido y cuántos
///   temas junta.
/// - **Un grupo** (el desborde, los aislados): cuántos temas junta.
/// - **Un tema**: cuántos documentos tiene, con cuántos temas se une y los más
///   unidos, y en qué comunidad está.
/// - **Un documento**: con qué documentos se lo ve vinculado —en [scene], o en
///   [tree] si solo está ahí: lo que el árbol trajo de la base al
///   desplegarlo— y por qué tema se llega a él (`insights.search`).
///
/// Es puro y barato: un tema recorre las uniones del grafo una vez; lo demás
/// mira lo ya calculado. No consulta la base ni rehace el grafo.
MapNodeFacts? mapNodeFacts(
  MapNodeRef ref, {
  required TopicGraph graph,
  required CommunityDetection detection,
  required CommunityOverview overview,
  required MapInsights insights,
  required GraphScene scene,
  CanvasTree? tree,
  TopicGraphWeights weights = const TopicGraphWeights(),
}) => switch (ref) {
  MapCommunityRef(:final index) => _communityFacts(
    ref,
    index,
    graph,
    overview,
    insights,
  ),
  MapTopicRef(:final valueId) => _topicFacts(
    ref,
    valueId,
    graph,
    detection,
    insights,
    weights,
  ),
  MapDocumentRef(:final itemId) => _documentFacts(
    ref,
    itemId,
    graph,
    insights,
    scene,
    tree,
  ),
};

/// Lo que dice la ficha de cada nodo, recordado mientras no cambie lo que la
/// arma —el mapa, lo que se dibuja, el árbol—: abrir otra vez la misma ficha,
/// o volver a dibujarla, no vuelve a mirar nada. Si cambia cualquiera, se
/// olvida todo.
class MapNodeFactsMemo {
  final _facts = <MapNodeRef, MapNodeFacts?>{};
  List<Object?> _inputs = const [];

  /// Lo que dice la ficha de [ref]: ver [mapNodeFacts].
  MapNodeFacts? of(
    MapNodeRef ref, {
    required TopicGraph graph,
    required CommunityDetection detection,
    required CommunityOverview overview,
    required MapInsights insights,
    required GraphScene scene,
    CanvasTree? tree,
  }) {
    final inputs = [graph, detection, overview, insights, scene, tree];
    var same = inputs.length == _inputs.length;
    for (var i = 0; same && i < inputs.length; i++) {
      same = identical(inputs[i], _inputs[i]);
    }
    if (!same) {
      _facts.clear();
      _inputs = inputs;
    }
    return _facts.putIfAbsent(
      ref,
      () => mapNodeFacts(
        ref,
        graph: graph,
        detection: detection,
        overview: overview,
        insights: insights,
        scene: scene,
        tree: tree,
      ),
    );
  }
}

MapNodeFacts? _communityFacts(
  MapCommunityRef ref,
  int index,
  TopicGraph graph,
  CommunityOverview overview,
  MapInsights insights,
) {
  if (index < 0 || index >= overview.nodes.length) return null;
  final node = overview.nodes[index];
  if (node.kind != OverviewKind.community) {
    return MapNodeFacts(
      ref: ref,
      kind: MapNodeKind.group,
      title: '',
      topicCount: node.topicCount,
    );
  }

  final communityId = node.communityIds.first;
  final profile = insights.communities.of(communityId);
  final anchor = node.anchor;
  final anchorLabel = anchor == null ? '' : graph.nodes[anchor].label;
  final name = profile?.name ?? '';
  final topics = profile?.topics ?? node.members;

  // La comunidad de cada identidad, en el panorama: una chica puede estar
  // dentro del desborde, y es ahí adonde se va.
  final overviewOf = <int, int>{
    for (var i = 0; i < overview.nodes.length; i++)
      for (final id in overview.nodes[i].communityIds) id: i,
  };
  final neighbors = <MapNodeNeighbor>[];
  for (final link in profile?.neighbors ?? const <CommunityLink>[]) {
    if (neighbors.length == kMapNodeNeighbors) break;
    final at = overviewOf[link.communityId];
    final other = insights.communities.of(link.communityId);
    if (at == null || other == null || other.nameLabels.isEmpty) continue;
    neighbors.add(
      MapNodeNeighbor(
        ref: MapCommunityRef(at),
        label: other.name,
        shortLabel: other.nameLabels.first,
      ),
    );
  }

  final latestId = profile?.latestItemId;
  final latestLabel = latestId == null
      ? null
      : insights.search.document(latestId)?.label;

  return MapNodeFacts(
    ref: ref,
    kind: MapNodeKind.community,
    title: name.isEmpty ? anchorLabel : name,
    group: communityId,
    nameLabels:
        profile?.nameLabels ?? [if (anchorLabel.isNotEmpty) anchorLabel],
    topicNames: [
      for (final topic in topics.take(kMapNodeTopicNames))
        graph.nodes[topic].label,
    ],
    topicCount: topics.length,
    documentCount: profile?.documentCount,
    linkCount: profile?.linkCount,
    neighbors: neighbors,
    latest: latestId == null || latestLabel == null
        ? null
        : MapNodeNeighbor(ref: MapDocumentRef(latestId), label: latestLabel),
  );
}

MapNodeFacts? _topicFacts(
  MapTopicRef ref,
  String valueId,
  TopicGraph graph,
  CommunityDetection detection,
  MapInsights insights,
  TopicGraphWeights weights,
) {
  final index = graph.indexOf(valueId);
  if (index == null) return null;

  // Lo que lo une con cada tema, en una pasada por las uniones.
  final weightTo = <int, double>{};
  for (final edge in graph.edges) {
    final other = edge.a == index
        ? edge.b
        : edge.b == index
        ? edge.a
        : null;
    if (other == null) continue;
    final weight = weights.of(edge);
    if (weight <= 0) continue;
    weightTo[other] = (weightTo[other] ?? 0) + weight;
  }
  final strongest = weightTo.keys.toList()
    ..sort((x, y) {
      final byWeight = weightTo[y]!.compareTo(weightTo[x]!);
      return byWeight != 0 ? byWeight : x.compareTo(y);
    });

  final community = index < detection.communityOf.length
      ? detection.communityOf[index]
      : null;
  final within = community == null
      ? null
      : insights.communities.of(community)?.name;

  return MapNodeFacts(
    ref: ref,
    kind: MapNodeKind.topic,
    title: graph.nodes[index].label,
    group: community,
    topicCount: weightTo.length,
    documentCount: graph.nodes[index].itemCount,
    neighbors: [
      for (final other in strongest.take(kMapNodeNeighbors))
        MapNodeNeighbor(
          ref: MapTopicRef(graph.nodes[other].valueId),
          label: graph.nodes[other].label,
        ),
    ],
    within: within == null || within.isEmpty ? null : within,
  );
}

MapNodeFacts? _documentFacts(
  MapDocumentRef ref,
  String itemId,
  TopicGraph graph,
  MapInsights insights,
  GraphScene scene,
  CanvasTree? tree,
) {
  final entry = insights.search.document(itemId);
  final at = scene.indexOf(ref.sceneKey);
  final drawn = at == null ? null : scene.nodes[at];
  final branch = drawn == null ? tree?.entries[ref.sceneKey] : null;
  final title = drawn?.label ?? entry?.label ?? branch?.title;
  if (title == null) return null;
  final isNote = switch ((drawn, entry)) {
    (final drawn?, _) => drawn.kind == SceneKind.note,
    (null, final entry?) => entry.isNote,
    (null, null) => branch!.isNote,
  };
  if (branch != null) {
    return _branchFacts(ref, branch, tree!, title, isNote, graph, entry);
  }

  // Con qué se lo ve vinculado: lo que une a los dos, sumado si son varios.
  final weightTo = <int, double>{};
  var links = 0;
  if (at != null) {
    for (final edge in scene.edges) {
      final other = edge.a == at
          ? edge.b
          : edge.b == at
          ? edge.a
          : null;
      if (other == null || other == at) continue;
      links++;
      weightTo[other] = (weightTo[other] ?? 0) + edge.weight;
    }
  }
  final strongest = weightTo.keys.toList()
    ..sort((x, y) {
      final byWeight = weightTo[y]!.compareTo(weightTo[x]!);
      return byWeight != 0 ? byWeight : x.compareTo(y);
    });

  return MapNodeFacts(
    ref: ref,
    kind: isNote ? MapNodeKind.note : MapNodeKind.source,
    title: title,
    linkCount: at == null ? null : links,
    neighbors: [
      for (final other in strongest.take(kMapNodeNeighbors))
        if (scene.nodes[other].ref case final id?)
          MapNodeNeighbor(
            ref: MapDocumentRef(id),
            label: scene.nodes[other].label,
          ),
    ],
    place: _placeOf(graph, entry?.topicValueId),
  );
}

/// La ficha de un documento que solo está en el árbol: lo vinculado con él
/// es lo que cuelga de él por un vínculo y, si él cuelga de otro documento
/// por uno, ese.
MapNodeFacts _branchFacts(
  MapDocumentRef ref,
  CanvasTreeEntry branch,
  CanvasTree tree,
  String title,
  bool isNote,
  TopicGraph graph,
  MapSearchEntry? entry,
) {
  final linked = <CanvasTreeEntry>[
    if (branch.edge == CanvasTreeEdge.relation)
      if (tree.entries[branch.parentKey] case final parent?) parent,
    for (final child in tree.entries.values)
      if (child.parentKey == branch.key &&
          child.edge == CanvasTreeEdge.relation)
        child,
  ];
  return MapNodeFacts(
    ref: ref,
    kind: isNote ? MapNodeKind.note : MapNodeKind.source,
    title: title,
    linkCount: linked.length,
    neighbors: [
      for (final other in linked.take(kMapNodeNeighbors))
        if (other.ref.kind == CanvasTreeKind.item)
          MapNodeNeighbor(
            ref: MapDocumentRef(other.ref.id),
            label: other.title,
          ),
    ],
    place: _placeOf(graph, entry?.topicValueId),
  );
}

/// El tema [valueId] como lugar de un documento, si está en el mapa.
MapNodeNeighbor? _placeOf(TopicGraph graph, String? valueId) {
  final at = valueId == null ? null : graph.indexOf(valueId);
  return at == null
      ? null
      : MapNodeNeighbor(
          ref: MapTopicRef(valueId!),
          label: graph.nodes[at].label,
        );
}
