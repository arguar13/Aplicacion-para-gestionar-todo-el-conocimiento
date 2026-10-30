import 'dart:typed_data';

import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';
import 'package:sinapsis/features/map/domain/services/topic_graph_builder.dart';

/// Lo que comparten las pruebas de lo que el motor sabe además de las
/// comunidades (F44): mapas chicos armados a mano, con las comunidades
/// puestas a mano para que cada prueba diga exactamente cuál es cuál.

/// Una entrada con los temas [values] —su nombre es el identificador con
/// mayúscula, salvo que [labels] diga otro— y un documento por cada lista de
/// [items], llamado `i0`, `i1`…
TopicGraphInput inputOf(
  List<String> values,
  List<List<String>> items, {
  Map<String, String> labels = const {},
  Map<String, String> parents = const {},
  List<TopicRelation> relations = const [],
  List<TopicItem> unassigned = const [],
  Map<String, DateTime> itemDates = const {},
  DateTime? readAt,
}) => TopicGraphInput(
  definitionId: 'tema',
  definitionName: 'Tema',
  values: [
    for (final id in values)
      AtlasValueRow(
        id: id,
        label: labels[id] ?? '${id[0].toUpperCase()}${id.substring(1)}',
        parentId: parents[id],
      ),
  ],
  items: [
    for (var i = 0; i < items.length; i++)
      TopicItem(
        id: 'i$i',
        valueIds: items[i],
        title: 'Documento $i',
        createdAt: itemDates['i$i'],
      ),
  ],
  relations: relations,
  unassigned: unassigned,
  readAt: readAt,
);

/// [times] documentos con los mismos temas.
List<List<String>> repeat(int times, List<String> topics) => [
  for (var i = 0; i < times; i++) topics,
];

/// Un mapa armado: el grafo, sus uniones y sus comunidades.
typedef BuiltMap = ({
  TopicGraph graph,
  TopicAdjacency adjacency,
  CommunityDetection detection,
});

/// El grafo de [input] con las comunidades de [communityOf] —la identidad de
/// la comunidad de cada valor—, sin pasar por la propagación.
BuiltMap mapOf(TopicGraphInput input, Map<String, int> communityOf) {
  final graph = buildTopicGraph(input);
  final adjacency = TopicAdjacency.of(
    graph,
    const TopicGraphWeights(),
    kHierarchyWeight,
  );
  return (
    graph: graph,
    adjacency: adjacency,
    detection: detectionOf(graph, adjacency, communityOf),
  );
}

/// Las comunidades de [communityOf], con la forma que les da el detector: de
/// la más grande a la más chica y, a igual tamaño, por identidad.
CommunityDetection detectionOf(
  TopicGraph graph,
  TopicAdjacency adjacency,
  Map<String, int> communityOf,
) {
  final n = graph.nodes.length;
  final ids = Int32List(n);
  final members = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    final id = communityOf[graph.nodes[i].valueId]!;
    ids[i] = id;
    (members[id] ??= []).add(i);
  }
  final order = members.keys.toList()
    ..sort((x, y) {
      final bySize = members[y]!.length.compareTo(members[x]!.length);
      return bySize != 0 ? bySize : x.compareTo(y);
    });
  return CommunityDetection(
    communityOf: ids,
    communities: [
      for (final id in order)
        TopicCommunity(
          id: id,
          members: members[id]!,
          anchor: members[id]!.first,
          isIsolated:
              members[id]!.length == 1 &&
              adjacency.degreeOf(members[id]!.first) == 0,
        ),
    ],
    memory: CommunityMemory(
      byValueId: {for (var i = 0; i < n; i++) graph.nodes[i].valueId: ids[i]},
      nextId: (order.isEmpty ? -1 : order.reduce((a, b) => a > b ? a : b)) + 1,
    ),
    passes: 0,
    converged: true,
    reassigned: 0,
  );
}
