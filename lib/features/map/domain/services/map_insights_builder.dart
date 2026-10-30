import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_insights.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/bridge_finder.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/community_links.dart';
import 'package:sinapsis/features/map/domain/services/community_profiler.dart';
import 'package:sinapsis/features/map/domain/services/map_recent_builder.dart';
import 'package:sinapsis/features/map/domain/services/map_search_builder.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';
import 'package:sinapsis/features/map/domain/services/unthemed_bubble_builder.dart';

/// Lo que el motor sabe además de las comunidades (F44): los puentes, lo que se
/// sabe de cada comunidad, el índice de búsqueda, la burbuja «Sin tema» y lo
/// nuevo. Corre en el isolate del cálculo, después de agrupar, con las mismas
/// uniones ([adjacency]) que usaron las comunidades.
///
/// [past] es el grafo de hace `kRecentMonthDays` días
/// (`buildTopicGraphHistory`), o `null` si desde entonces no cambió nada: solo
/// entonces se vuelve a agrupar, partiendo de las comunidades de hoy, para
/// saber cuántas había.
MapInsights buildMapInsights({
  required TopicGraphInput input,
  required TopicGraph graph,
  required CommunityDetection detection,
  required TopicAdjacency adjacency,
  TopicGraph? past,
}) {
  final links = CommunityLinks.of(adjacency, detection);
  final search = buildMapSearchIndex(
    graph: graph,
    detection: detection,
    input: input,
  );
  final communitiesBefore = past == null
      ? connectedCommunities(detection)
      : connectedCommunities(
          detectCommunities(past, previous: detection.memory),
        );
  return MapInsights(
    bridges: findBridges(adjacency, links),
    communities: profileCommunities(
      graph: graph,
      detection: detection,
      adjacency: adjacency,
      links: links,
      input: input,
    ),
    search: search,
    unthemed: buildUnthemedBubble(input: input, search: search),
    recent: buildMapRecent(
      input: input,
      graph: graph,
      detection: detection,
      search: search,
      communitiesBefore: communitiesBefore,
    ),
  );
}
