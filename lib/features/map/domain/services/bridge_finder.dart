import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/services/community_links.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';

/// Cuántos puentes se entregan, como mucho: los que se marcan en el lienzo y
/// los que lista el Resumen.
const kMaxBridges = 12;

/// Cuántas comunidades unidas se nombran de cada puente, como mucho.
const kMaxBridgeJoins = 6;

/// Los temas que más unen comunidades distintas (F44): los puentes.
///
/// Un tema es puente si une al menos dos comunidades: la suya —si tiene alguna
/// unión con otro tema de ella— y otra, o dos que no son la suya. Un tema
/// suelto que solo cuelga de otra comunidad no une nada: es un satélite.
///
/// Cuánto une ([TopicBridge.score]) es, por cada otra comunidad que toca, lo
/// que pesan sus uniones con ella por la parte que lleva de TODO lo que une a
/// las dos comunidades. Así cuenta tanto cuánto une como cuán imprescindible
/// es: el único camino entre dos comunidades vale todo su peso, y uno entre
/// cien caminos parecidos, casi nada. Es lo que dice «si se sacara, dejaría
/// dos partes sueltas» sin tener que sacar cada tema y volver a mirar el mapa
/// —eso costaría el cuadrado—.
///
/// El costo es lineal en temas y uniones, y ese es el tope: cada tema suma lo
/// que lo une a cada comunidad con una lista de lo tocado y no con una fila
/// por comunidad —con dos mil temas y dos mil comunidades serían cuatro
/// millones de casilleros—, los pares de comunidades son solo los que se
/// tocan ([CommunityLinks]) y las uniones de cada puente se arman después, y
/// solo para los [limit] que se entregan, con a lo sumo [maxJoins] cada uno.
/// [BridgeAnalysis.visits] cuenta lo recorrido.
///
/// Es determinista: a igual puntaje gana el que une más comunidades y, a
/// igual cantidad, el de menor posición, que es por nombre.
BridgeAnalysis findBridges(
  TopicAdjacency adjacency,
  CommunityLinks links, {
  int limit = kMaxBridges,
  int maxJoins = kMaxBridgeJoins,
}) {
  final n = adjacency.nodeCount;
  final c = links.ids.length;
  if (n == 0 || c < 2) {
    return BridgeAnalysis(
      bridges: const [],
      topics: const {},
      candidates: 0,
      visits: links.visits,
    );
  }

  final community = links.communityOfTopic;
  var visits = links.visits;

  // Lo que une a un tema con cada comunidad que toca: un casillero por
  // comunidad, pero solo se miran —y se vuelven a cero— los tocados.
  final tally = Float64List(c);
  final edgeCount = Int32List(c);
  final touched = Int32List(c);

  final score = Float64List(n);
  final joined = Int32List(n);
  final sole = Int32List(n);
  final candidates = <int>[];

  for (var i = 0; i < n; i++) {
    final own = community[i];
    var touchedCount = 0;
    var internal = false;
    for (var e = adjacency.offsets[i]; e < adjacency.offsets[i + 1]; e++) {
      visits++;
      final other = community[adjacency.neighbors[e]];
      if (other == own) {
        internal = true;
        continue;
      }
      if (edgeCount[other] == 0) touched[touchedCount++] = other;
      tally[other] += adjacency.weights[e];
      edgeCount[other]++;
    }

    var total = 0.0;
    var soleCount = 0;
    for (var t = 0; t < touchedCount; t++) {
      final other = touched[t];
      final share = tally[other] / links.weightBetween(own, other);
      total += tally[other] * share;
      // Única si TODAS las uniones entre las dos comunidades son suyas: se
      // cuentan, no se comparan sumas de decimales.
      if (edgeCount[other] == links.countBetween(own, other)) soleCount++;
      tally[other] = 0;
      edgeCount[other] = 0;
    }

    if (touchedCount + (internal ? 1 : 0) < 2) continue;
    score[i] = total;
    joined[i] = touchedCount;
    sole[i] = soleCount;
    candidates.add(i);
  }

  final ranked = [...candidates]
    ..sort((x, y) {
      final byScore = score[y].compareTo(score[x]);
      if (byScore != 0) return byScore;
      final byJoined = joined[y].compareTo(joined[x]);
      return byJoined != 0 ? byJoined : x.compareTo(y);
    });
  final chosen = ranked.length <= limit ? ranked : ranked.sublist(0, limit);

  final bridges = <TopicBridge>[];
  for (final i in chosen) {
    final own = community[i];
    var touchedCount = 0;
    for (var e = adjacency.offsets[i]; e < adjacency.offsets[i + 1]; e++) {
      visits++;
      final other = community[adjacency.neighbors[e]];
      if (other == own) continue;
      if (edgeCount[other] == 0) touched[touchedCount++] = other;
      tally[other] += adjacency.weights[e];
      edgeCount[other]++;
    }
    final joins = <BridgeJoin>[];
    for (var t = 0; t < touchedCount; t++) {
      final other = touched[t];
      joins.add(
        BridgeJoin(
          communityId: links.ids[other],
          weight: tally[other],
          share: edgeCount[other] == links.countBetween(own, other)
              ? 1
              : tally[other] / links.weightBetween(own, other),
        ),
      );
      tally[other] = 0;
      edgeCount[other] = 0;
    }
    joins.sort((x, y) {
      final byWeight = y.weight.compareTo(x.weight);
      return byWeight != 0
          ? byWeight
          : links.denseOf[x.communityId]!.compareTo(
              links.denseOf[y.communityId]!,
            );
    });
    bridges.add(
      TopicBridge(
        topic: i,
        communityId: links.ids[own],
        score: score[i],
        joins: joins.length <= maxJoins ? joins : joins.sublist(0, maxJoins),
        joinedCount: joined[i],
        soleCount: sole[i],
      ),
    );
  }

  return BridgeAnalysis(
    bridges: bridges,
    topics: {for (final bridge in bridges) bridge.topic},
    candidates: candidates.length,
    visits: visits,
  );
}
