import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Arma el índice de búsqueda del mapa (F44): cada tema con su comunidad, y
/// cada documento —con tema o sin él— con la comunidad y el tema por los que
/// se llega a él ([placeDocument]).
///
/// Cada nombre se pasa sin acentos ni mayúsculas UNA vez, acá, en el isolate
/// del cálculo: buscar después solo compara.
MapSearchIndex buildMapSearchIndex({
  required TopicGraph graph,
  required CommunityDetection detection,
  required TopicGraphInput input,
}) {
  final sizeOf = {
    for (final community in detection.communities)
      community.id: community.members.length,
  };

  final topics = <MapSearchEntry>[
    for (var i = 0; i < graph.nodes.length; i++)
      MapSearchEntry(
        kind: MapSearchKind.topic,
        id: graph.nodes[i].valueId,
        label: graph.nodes[i].label,
        key: normalizeVocabularyLabel(graph.nodes[i].label),
        communityId: detection.communityOf[i],
        topicValueId: graph.nodes[i].valueId,
        size: graph.nodes[i].itemCount,
      ),
  ];

  MapSearchEntry documentOf(TopicItem item) {
    final place = placeDocument(item, graph, detection, sizeOf);
    return MapSearchEntry(
      kind: MapSearchKind.document,
      id: item.id,
      label: item.title,
      key: normalizeVocabularyLabel(item.title),
      communityId: place?.communityId,
      topicValueId: place?.valueId,
      valueIds: item.valueIds,
      isNote: item.isNote,
      createdAt: item.createdAt,
    );
  }

  final documents = <MapSearchEntry>[
    for (final item in input.items) documentOf(item),
    for (final item in input.unassigned) documentOf(item),
  ];

  int byKey(MapSearchEntry a, MapSearchEntry b) {
    final byKey = a.key.compareTo(b.key);
    return byKey != 0 ? byKey : a.id.compareTo(b.id);
  }

  topics.sort(byKey);
  documents.sort(byKey);
  final entries = [...topics, ...documents];
  return MapSearchIndex(
    entries: entries,
    topicAt: {for (var i = 0; i < topics.length; i++) topics[i].id: i},
    documentAt: {
      for (var i = 0; i < documents.length; i++)
        documents[i].id: topics.length + i,
    },
  );
}

/// Dónde está un documento en el mapa: una comunidad y uno de sus temas.
typedef DocumentPlace = ({int communityId, String valueId});

/// Por dónde se llega a [item] en el mapa, o `null` si no tiene ningún tema
/// del grafo —entonces está en la burbuja «Sin tema»—.
///
/// La comunidad es la de la mayoría de sus temas; a igual cantidad, la más
/// grande —en [sizeOf], la cantidad de temas de cada una— y, a igual tamaño,
/// la de menor identidad. Dentro de ella, el tema más específico: el de menos
/// documentos propios, porque el nivel de los documentos de un tema dibuja
/// como mucho `kMaxGraphItems`, y en el más chico es donde seguro se ve. A
/// igual cantidad, el de menor posición, que es por nombre.
DocumentPlace? placeDocument(
  TopicItem item,
  TopicGraph graph,
  CommunityDetection detection,
  Map<int, int> sizeOf,
) {
  final positions = <int>[];
  for (final valueId in item.valueIds) {
    final position = graph.indexOf(valueId);
    if (position != null && !positions.contains(position)) {
      positions.add(position);
    }
  }
  if (positions.isEmpty) return null;

  final votes = <int, int>{};
  for (final position in positions) {
    votes.update(
      detection.communityOf[position],
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  var community = -1;
  for (final MapEntry(key: id, value: count) in votes.entries) {
    if (community == -1) {
      community = id;
      continue;
    }
    final byVotes = count.compareTo(votes[community]!);
    final bySize = (sizeOf[id] ?? 0).compareTo(sizeOf[community] ?? 0);
    if (byVotes > 0 ||
        (byVotes == 0 && (bySize > 0 || (bySize == 0 && id < community)))) {
      community = id;
    }
  }

  var best = -1;
  for (final position in positions) {
    if (detection.communityOf[position] != community) continue;
    if (best == -1) {
      best = position;
      continue;
    }
    final byItems = graph.nodes[position].itemCount.compareTo(
      graph.nodes[best].itemCount,
    );
    if (byItems < 0 || (byItems == 0 && position < best)) best = position;
  }
  return (communityId: community, valueId: graph.nodes[best].valueId);
}
