import 'dart:collection';

import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';

/// Arma la burbuja «Sin tema» (F44) con los documentos sin ningún valor de lo
/// que se mira.
///
/// Al entrar se dibujan como el nivel de los documentos de un tema: los
/// procesados más recientemente primero —lo que no tiene fecha, al final—,
/// como mucho [limit], con los vínculos entre ellos. Y se cuentan sus vínculos
/// con los documentos con tema, por la comunidad donde está cada uno
/// ([search]): es lo que une la burbuja con el resto del panorama.
UnthemedBubble buildUnthemedBubble({
  required TopicGraphInput input,
  required MapSearchIndex search,
  int limit = kMaxGraphItems,
}) {
  final unthemed = input.unassigned;
  if (unthemed.isEmpty) return const UnthemedBubble.empty();

  final ordered = [...unthemed]
    ..sort((x, y) {
      final a = x.createdAt;
      final b = y.createdAt;
      if (a != null && b != null) {
        final byDate = b.compareTo(a);
        if (byDate != 0) return byDate;
      } else if (a != null || b != null) {
        return a == null ? 1 : -1;
      }
      return x.id.compareTo(y.id);
    });
  final shown = ordered.length <= limit ? ordered : ordered.sublist(0, limit);
  final positionOf = {for (var i = 0; i < shown.length; i++) shown[i].id: i};
  final ids = HashSet<String>.of([for (final item in unthemed) item.id]);

  final edges = <TopicItemEdge>[];
  final linked = HashSet<String>();
  final perCommunity = <int, int>{};
  for (final relation in input.relations) {
    final from = relation.fromItemId;
    final to = relation.toItemId;
    if (from == to) continue;
    final fromInside = ids.contains(from);
    final toInside = ids.contains(to);
    if (!fromInside && !toInside) continue;
    if (fromInside) linked.add(from);
    if (toInside) linked.add(to);

    if (fromInside && toInside) {
      final a = positionOf[from];
      final b = positionOf[to];
      if (a != null && b != null) {
        edges.add(TopicItemEdge(a: a, b: b, kind: relation.kind));
      }
      continue;
    }
    // Un extremo con tema: el vínculo une la burbuja con su comunidad.
    final community = search.document(fromInside ? to : from)?.communityId;
    if (community != null) {
      perCommunity.update(community, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  final communities =
      [
        for (final MapEntry(key: id, value: count) in perCommunity.entries)
          CommunityLink(communityId: id, weight: count.toDouble()),
      ]..sort((x, y) {
        final byWeight = y.weight.compareTo(x.weight);
        return byWeight != 0
            ? byWeight
            : x.communityId.compareTo(y.communityId);
      });

  return UnthemedBubble(
    count: unthemed.length,
    items: TopicItemsGraph(
      valueId: kUnthemedBubbleId,
      items: [
        for (final item in shown)
          TopicItemNode(id: item.id, title: item.title, isNote: item.isNote),
      ],
      edges: edges,
      truncated: unthemed.length > shown.length,
    ),
    communities: communities,
    linkedCount: linked.length,
  );
}
