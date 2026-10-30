import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_recent.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// El comienzo de la ventana de [days] días que termina en [now].
DateTime recentSince(DateTime now, int days) =>
    now.subtract(Duration(days: days));

/// Cuántas comunidades con uniones tiene [detection]: los temas aislados no
/// cuentan, como en el Resumen.
int connectedCommunities(CommunityDetection detection) =>
    detection.communities.where((c) => !c.isIsolated).length;

/// Arma lo nuevo del mapa (F44): lo procesado y lo vinculado de la semana y
/// del mes, y las cuatro cifras con lo que valían hace [kRecentMonthDays]
/// días.
///
/// Mide contra `TopicGraphInput.readAt`; sin él, nada es nuevo y las cifras no
/// cambian. Lo que no tiene fecha cuenta como de siempre. Cada documento sale
/// con su lugar en el mapa ([search]), para verlo con un toque.
///
/// [communitiesBefore] es cuántas comunidades con uniones tenía el grafo de
/// hace un mes (`buildTopicGraphHistory`): agruparlo es trabajo del motor, no
/// de acá.
MapRecent buildMapRecent({
  required TopicGraphInput input,
  required TopicGraph graph,
  required CommunityDetection detection,
  required MapSearchIndex search,
  required int communitiesBefore,
}) {
  final now = input.readAt;
  final communities = connectedCommunities(detection);
  final documents = [...input.items, ...input.unassigned];
  final links = [
    for (final relation in input.relations)
      if (relation.fromItemId != relation.toItemId) relation,
  ];
  if (now == null) {
    return MapRecent(
      at: null,
      week: const RecentWindow.none(kRecentWeekDays),
      month: const RecentWindow.none(kRecentMonthDays),
      figures: MapFigures(
        documents: FigureChange(
          now: documents.length,
          before: documents.length,
        ),
        topics: FigureChange(
          now: graph.nodes.length,
          before: graph.nodes.length,
        ),
        communities: FigureChange(now: communities, before: communities),
        links: FigureChange(now: links.length, before: links.length),
      ),
    );
  }

  /// Si [at] cae en la ventana que empieza en [since]: lo que no tiene fecha,
  /// nunca.
  bool within(DateTime? at, DateTime since) =>
      at != null && !at.isBefore(since);

  RecentWindow window(int days) {
    final since = recentSince(now, days);
    final processed = [
      for (final item in documents)
        if (within(item.createdAt, since)) item,
    ]..sort((x, y) => _newestFirst(x.createdAt!, x.id, y.createdAt!, y.id));
    final linked =
        [
          for (final relation in links)
            if (within(relation.createdAt, since)) relation,
        ]..sort(
          (x, y) => _newestFirst(
            x.createdAt!,
            '${x.fromItemId}\u0000${x.toItemId}',
            y.createdAt!,
            '${y.fromItemId}\u0000${y.toItemId}',
          ),
        );

    final named = <RecentLink>[];
    for (final relation in linked) {
      if (named.length == kRecentListLength) break;
      final from = search.document(relation.fromItemId);
      final to = search.document(relation.toItemId);
      if (from == null || to == null) continue;
      named.add(
        RecentLink(
          from: from,
          to: to,
          kind: relation.kind,
          at: relation.createdAt!,
        ),
      );
    }

    return RecentWindow(
      days: days,
      processedCount: processed.length,
      processed: [
        for (final item in processed.take(kRecentListLength))
          if (search.document(item.id) case final entry?) entry,
      ],
      linkedCount: linked.length,
      linked: named,
    );
  }

  final monthStart = recentSince(now, kRecentMonthDays);
  int olderCount<T>(Iterable<T> all, DateTime? Function(T) dateOf) =>
      all.where((x) => !within(dateOf(x), monthStart)).length;

  return MapRecent(
    at: now,
    week: window(kRecentWeekDays),
    month: window(kRecentMonthDays),
    figures: MapFigures(
      documents: FigureChange(
        now: documents.length,
        before: olderCount(documents, (item) => item.createdAt),
      ),
      topics: FigureChange(
        now: graph.nodes.length,
        before: olderCount(
          graph.nodes,
          (node) => input.valueCreatedAt[node.valueId],
        ),
      ),
      communities: FigureChange(now: communities, before: communitiesBefore),
      // Un vínculo existía si se hizo antes y sus dos documentos ya estaban.
      links: FigureChange(
        now: links.length,
        before: _linksBefore(links, documents, monthStart),
      ),
    ),
  );
}

int _linksBefore(
  List<TopicRelation> links,
  List<TopicItem> documents,
  DateTime since,
) {
  final newer = {
    for (final item in documents)
      if (item.createdAt case final at? when !at.isBefore(since)) item.id,
  };
  var count = 0;
  for (final relation in links) {
    final at = relation.createdAt;
    if (at != null && !at.isBefore(since)) continue;
    if (newer.contains(relation.fromItemId) ||
        newer.contains(relation.toItemId)) {
      continue;
    }
    count++;
  }
  return count;
}

/// Lo más nuevo primero y, a igual fecha, por [xKey] y [yKey]: el orden no
/// depende de cómo llegaron.
int _newestFirst(DateTime x, String xKey, DateTime y, String yKey) {
  final byDate = y.compareTo(x);
  return byDate != 0 ? byDate : xKey.compareTo(yKey);
}
