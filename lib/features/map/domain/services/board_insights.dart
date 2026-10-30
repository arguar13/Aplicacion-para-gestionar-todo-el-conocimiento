import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';

/// Cuántos días son «esta semana» en «Lo nuevo».
const kBoardRecentDays = 7;

/// Cuántos días mira el cambio de cada cifra grande («+3»).
const kBoardTrendDays = 30;

/// Cuántas filas trae cada lista de «Lo nuevo».
const kBoardNewRows = 5;

/// Cuántos temas trae cada lista de «Para estudiar».
const kBoardStudyRows = 5;

/// Cuántos documentos sueltos se nombran; los demás se cuentan.
const kBoardLooseRows = 6;

/// Las cifras grandes del Resumen, cada una con lo que sumó en los últimos
/// [kBoardTrendDays] días.
class BoardFigures {
  const BoardFigures({
    required this.documents,
    required this.documentsAdded,
    required this.topics,
    required this.topicsAdded,
    required this.communities,
    required this.communitiesAdded,
    required this.links,
    required this.linksAdded,
  });

  /// Los documentos procesados que pasan el filtro, tengan o no tema.
  final int documents;
  final int documentsAdded;

  /// Los temas (o etiquetas, o valores) de lo que se mira.
  final int topics;

  /// Los que recibieron su primer documento en estos días.
  final int topicsAdded;

  /// Las comunidades con uniones: un tema aislado no es una comunidad.
  final int communities;

  /// Las que nacieron en estos días: todos sus temas con material lo
  /// recibieron por primera vez en estos días.
  final int communitiesAdded;

  /// Los vínculos entre documentos.
  final int links;
  final int linksAdded;
}

/// Un documento de «Lo nuevo».
class BoardNewItem {
  const BoardNewItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.topic,
  });

  final String id;
  final String title;
  final DateTime createdAt;

  /// Su tema con más material, si tiene alguno: dónde cae en el Mapa.
  final TopicNode? topic;
}

/// Un vínculo de «Lo nuevo».
class BoardNewLink {
  const BoardNewLink({
    required this.fromId,
    required this.fromTitle,
    required this.toId,
    required this.toTitle,
    required this.createdAt,
  });

  final String fromId;
  final String fromTitle;
  final String toId;
  final String toTitle;
  final DateTime createdAt;
}

/// Un tema de «Para estudiar», con lo que hay para estudiar en él.
///
/// Cuenta como Repasar con ese tema en el selector: el tema **con sus ramas**
/// (un subtema suma a su padre) y, de cada documento, también las tarjetas de
/// su fuente.
class BoardStudyTopic {
  const BoardStudyTopic({
    required this.topic,
    required this.documents,
    required this.cards,
    required this.dueToday,
  });

  final TopicNode topic;

  /// Cuántos documentos tiene, contando los de sus ramas.
  final int documents;
  final int cards;
  final int dueToday;
}

/// Un documento sin ningún vínculo.
class BoardLooseItem {
  const BoardLooseItem({required this.id, required this.title});

  final String id;
  final String title;
}

/// Lo que el Resumen cuenta además de `BoardStats`: las cifras con su cambio,
/// lo nuevo de la semana, para estudiar y lo suelto.
class BoardInsights {
  const BoardInsights({
    required this.figures,
    required this.newItems,
    required this.newItemCount,
    required this.newLinks,
    required this.newLinkCount,
    required this.dueTopics,
    required this.uncardedTopics,
    required this.looseItems,
    required this.looseItemIds,
  });

  final BoardFigures figures;

  /// Lo procesado en los últimos [kBoardRecentDays] días, lo último primero:
  /// a lo sumo [kBoardNewRows].
  final List<BoardNewItem> newItems;

  /// Cuántos documentos se procesaron en esos días, en total.
  final int newItemCount;

  /// Lo vinculado en esos días, lo último primero: a lo sumo [kBoardNewRows].
  final List<BoardNewLink> newLinks;
  final int newLinkCount;

  /// Los temas con tarjetas para hoy, los de más tarjetas primero.
  final List<BoardStudyTopic> dueTopics;

  /// Los temas con material y ninguna tarjeta, los de más material primero.
  final List<BoardStudyTopic> uncardedTopics;

  /// Los primeros documentos sin ningún vínculo, lo último que llegó primero:
  /// a lo sumo [kBoardLooseRows].
  final List<BoardLooseItem> looseItems;

  /// Todos los documentos sin ningún vínculo, en el mismo orden: a ellos van
  /// «Sugerir vínculos» y «Organizar con IA».
  final List<String> looseItemIds;
}

/// Arma lo que el Resumen cuenta con [facts] y [cards], sobre el grafo de
/// temas y las comunidades del mapa, a la hora [now].
///
/// Es puro y lineal en documentos, vínculos y temas (más la profundidad de la
/// jerarquía, para sumar cada subtema a su padre). Sin empates que dependan
/// del orden en que llegaron los datos: a igual fecha, por id; a igual
/// cantidad, por la posición del tema, que es por nombre.
///
/// Lo calcula el Resumen mientras el motor del Mapa no lo entregue hecho (F44,
/// paso 1): cambiarlo por el del motor es cambiar quién llama.
BoardInsights buildBoardInsights({
  required TopicGraph graph,
  required CommunityDetection detection,
  required BoardFacts facts,
  required Map<String, BoardCardFact> cards,
  required DateTime now,
}) {
  final trendFrom = now.subtract(const Duration(days: kBoardTrendDays));
  final recentFrom = now.subtract(const Duration(days: kBoardRecentDays));
  final nodes = graph.nodes;
  final n = nodes.length;

  // Cuándo recibió cada tema su primer documento (directo).
  final firstMaterial = List<DateTime?>.filled(n, null);
  for (final item in facts.items) {
    for (final valueId in item.valueIds) {
      final i = graph.indexOf(valueId);
      if (i == null) continue;
      final first = firstMaterial[i];
      if (first == null || item.createdAt.isBefore(first)) {
        firstMaterial[i] = item.createdAt;
      }
    }
  }
  bool isNew(int topic) => !(firstMaterial[topic]?.isBefore(trendFrom) ?? true);

  var communities = 0;
  var communitiesAdded = 0;
  for (final community in detection.communities) {
    if (community.isIsolated) continue;
    communities++;
    final withMaterial = [
      for (final m in community.members)
        if (firstMaterial[m] != null) m,
    ];
    if (withMaterial.isNotEmpty && withMaterial.every(isNew)) {
      communitiesAdded++;
    }
  }

  final figures = BoardFigures(
    documents: facts.items.length,
    documentsAdded: facts.items
        .where((i) => !i.createdAt.isBefore(trendFrom))
        .length,
    topics: n,
    topicsAdded: [for (var i = 0; i < n; i++) i].where(isNew).length,
    communities: communities,
    communitiesAdded: communitiesAdded,
    links: facts.links.length,
    linksAdded: facts.links
        .where((l) => !l.createdAt.isBefore(trendFrom))
        .length,
  );

  // Lo nuevo de la semana.
  int byNewest(DateTime a, String aId, DateTime b, String bId) {
    final byDate = b.compareTo(a);
    return byDate != 0 ? byDate : aId.compareTo(bId);
  }

  final recentItems = [
    for (final item in facts.items)
      if (!item.createdAt.isBefore(recentFrom)) item,
  ]..sort((x, y) => byNewest(x.createdAt, x.id, y.createdAt, y.id));
  final titles = {for (final item in facts.items) item.id: item.title};
  final recentLinks =
      [
        for (final link in facts.links)
          if (!link.createdAt.isBefore(recentFrom)) link,
      ]..sort(
        (x, y) => byNewest(
          x.createdAt,
          '${x.fromId}\u0000${x.toId}',
          y.createdAt,
          '${y.fromId}\u0000${y.toId}',
        ),
      );

  // Lo suelto: los documentos sin ningún vínculo.
  final linked = <String>{
    for (final link in facts.links) ...[link.fromId, link.toId],
  };
  final loose = [
    for (final item in facts.items)
      if (!linked.contains(item.id)) item,
  ]..sort((x, y) => byNewest(x.createdAt, x.id, y.createdAt, y.id));

  final (:due, :uncarded) = _studyTopics(graph, facts.items, cards);

  return BoardInsights(
    figures: figures,
    newItems: [
      for (final item in recentItems.take(kBoardNewRows))
        BoardNewItem(
          id: item.id,
          title: item.title,
          createdAt: item.createdAt,
          topic: _mainTopic(graph, item.valueIds),
        ),
    ],
    newItemCount: recentItems.length,
    newLinks: [
      for (final link in recentLinks.take(kBoardNewRows))
        BoardNewLink(
          fromId: link.fromId,
          fromTitle: titles[link.fromId] ?? '',
          toId: link.toId,
          toTitle: titles[link.toId] ?? '',
          createdAt: link.createdAt,
        ),
    ],
    newLinkCount: recentLinks.length,
    dueTopics: due,
    uncardedTopics: uncarded,
    looseItems: [
      for (final item in loose.take(kBoardLooseRows))
        BoardLooseItem(id: item.id, title: item.title),
    ],
    looseItemIds: [for (final item in loose) item.id],
  );
}

/// El tema con más material de [valueIds]; a igual material, el primero por
/// nombre. `null` si ninguno está en el grafo.
TopicNode? _mainTopic(TopicGraph graph, List<String> valueIds) {
  int? best;
  for (final valueId in valueIds) {
    final i = graph.indexOf(valueId);
    if (i == null) continue;
    final current = best;
    if (current == null ||
        graph.nodes[i].itemCount > graph.nodes[current].itemCount ||
        (graph.nodes[i].itemCount == graph.nodes[current].itemCount &&
            i < current)) {
      best = i;
    }
  }
  return best == null ? null : graph.nodes[best];
}

/// Los temas con tarjetas para hoy y los que tienen material sin ninguna
/// tarjeta, contando cada tema con sus ramas, como Repasar.
///
/// Cada documento suma a sus temas y a los antepasados de cada uno, pero UNA
/// vez por tema aunque llegue por dos ramas: `seenBy` guarda, por tema, el
/// último documento que sumó.
({List<BoardStudyTopic> due, List<BoardStudyTopic> uncarded}) _studyTopics(
  TopicGraph graph,
  List<BoardItemFact> items,
  Map<String, BoardCardFact> cards,
) {
  final nodes = graph.nodes;
  final n = nodes.length;
  final parentOf = Int32List(n)..fillRange(0, n, -1);
  for (var i = 0; i < n; i++) {
    final parentId = nodes[i].parentId;
    if (parentId == null) continue;
    parentOf[i] = graph.indexOf(parentId) ?? -1;
  }

  final documents = Int32List(n);
  final cardCount = Int32List(n);
  final dueCount = Int32List(n);
  final seenBy = Int32List(n)..fillRange(0, n, -1);
  for (var k = 0; k < items.length; k++) {
    final item = items[k];
    final card = cards[item.id];
    for (final valueId in item.valueIds) {
      // Hacia arriba hasta la raíz, o hasta un tema que este documento ya
      // sumó: de ahí para arriba también lo sumó. El tope de pasos protege
      // de un ciclo en la jerarquía, que la base no debería tener.
      var i = graph.indexOf(valueId) ?? -1;
      var steps = 0;
      while (i != -1 && seenBy[i] != k && steps++ <= n) {
        seenBy[i] = k;
        documents[i]++;
        if (card != null) {
          cardCount[i] += card.cards;
          dueCount[i] += card.dueToday;
        }
        i = parentOf[i];
      }
    }
  }

  BoardStudyTopic topicAt(int i) => BoardStudyTopic(
    topic: nodes[i],
    documents: documents[i],
    cards: cardCount[i],
    dueToday: dueCount[i],
  );

  final due =
      [
        for (var i = 0; i < n; i++)
          if (dueCount[i] > 0) i,
      ]..sort((x, y) {
        final byDue = dueCount[y].compareTo(dueCount[x]);
        if (byDue != 0) return byDue;
        final byDocs = documents[y].compareTo(documents[x]);
        return byDocs != 0 ? byDocs : x.compareTo(y);
      });
  final uncarded =
      [
        for (var i = 0; i < n; i++)
          if (documents[i] > 0 && cardCount[i] == 0) i,
      ]..sort((x, y) {
        final byDocs = documents[y].compareTo(documents[x]);
        return byDocs != 0 ? byDocs : x.compareTo(y);
      });

  return (
    due: [for (final i in due.take(kBoardStudyRows)) topicAt(i)],
    uncarded: [for (final i in uncarded.take(kBoardStudyRows)) topicAt(i)],
  );
}
