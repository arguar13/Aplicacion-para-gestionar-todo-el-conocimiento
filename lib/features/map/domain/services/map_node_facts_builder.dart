import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/map_insights.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';

/// Cuántos vecinos nombra la ficha en «Une con».
const kMapNodeNeighbors = 3;

/// Cuántos temas de una comunidad nombra la ficha; los demás se cuentan.
const kMapNodeTopicNames = 8;

/// Lo que dice la ficha de [ref] (F44, paso 4), con lo que el lienzo ya tiene:
/// el grafo de temas y sus comunidades —[overview], lo que se ve de lejos—, lo
/// que el motor sabe ([insights]) y lo que se dibuja ([scene]). `null` si [ref]
/// no está en ninguno: un tema que ya no existe, un documento que no se ve ni
/// está en el mapa.
///
/// - **Una comunidad**: su nombre, sus temas, sus documentos y vínculos, con
///   qué comunidades se une más y lo más reciente, de `insights.communities`.
///   Sin eso —un mapa calculado sin `insights`—, su tema más unido y cuántos
///   temas junta.
/// - **Un grupo** (el desborde, los aislados): cuántos temas junta.
/// - **Un tema**: cuántos documentos tiene, con cuántos temas se une y los más
///   unidos, y en qué comunidad está.
/// - **Un documento**: con qué documentos se lo ve vinculado en [scene] y por
///   qué tema se llega a él (`insights.search`).
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
  ),
};

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
) {
  final entry = insights.search.document(itemId);
  final at = scene.indexOf(ref.sceneKey);
  final drawn = at == null ? null : scene.nodes[at];
  final title = drawn?.label ?? entry?.label;
  if (title == null) return null;
  final isNote = drawn == null ? entry!.isNote : drawn.kind == SceneKind.note;

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

  final placeId = entry?.topicValueId;
  final placeAt = placeId == null ? null : graph.indexOf(placeId);

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
    place: placeId == null || placeAt == null
        ? null
        : MapNodeNeighbor(
            ref: MapTopicRef(placeId),
            label: graph.nodes[placeAt].label,
          ),
  );
}
