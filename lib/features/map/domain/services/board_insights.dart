import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';

/// Cuántos temas trae cada lista de «Para estudiar».
const kBoardStudyRows = 5;

/// Cuántos documentos sueltos se nombran; los demás se cuentan.
const kBoardLooseRows = 6;

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

/// Lo que el Resumen cuenta por su cuenta, además de lo que el motor del Mapa
/// entrega con cada mapa (`MapInsights`: las cifras, lo nuevo y los puentes):
/// para estudiar y lo suelto.
///
/// «Para estudiar» es del Resumen y no del motor a propósito (decisión 47): las
/// tarjetas cambian al repasar, y el mapa no se recalcula por eso.
class BoardInsights {
  const BoardInsights({
    required this.dueTopics,
    required this.uncardedTopics,
    required this.looseItems,
    required this.looseItemIds,
  });

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

/// Arma «Para estudiar» y lo suelto con [facts] y [cards], sobre el grafo de
/// temas del mapa.
///
/// Es puro y lineal en documentos y vínculos (más la profundidad de la
/// jerarquía, para sumar cada subtema a su padre). Sin empates que dependan
/// del orden en que llegaron los datos: a igual fecha, por id; a igual
/// cantidad, por la posición del tema, que es por nombre.
BoardInsights buildBoardInsights({
  required TopicGraph graph,
  required BoardFacts facts,
  required Map<String, BoardCardFact> cards,
}) {
  final linked = <String>{
    for (final link in facts.links) ...[link.fromId, link.toId],
  };
  final loose =
      [
        for (final item in facts.items)
          if (!linked.contains(item.id)) item,
      ]..sort((x, y) {
        final byDate = y.createdAt.compareTo(x.createdAt);
        return byDate != 0 ? byDate : x.id.compareTo(y.id);
      });

  final (:due, :uncarded) = _studyTopics(graph, facts.items, cards);

  return BoardInsights(
    dueTopics: due,
    uncardedTopics: uncarded,
    looseItems: [
      for (final item in loose.take(kBoardLooseRows))
        BoardLooseItem(id: item.id, title: item.title),
    ],
    looseItemIds: [for (final item in loose) item.id],
  );
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
