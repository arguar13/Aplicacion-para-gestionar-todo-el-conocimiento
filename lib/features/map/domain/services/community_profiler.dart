import 'dart:collection';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/community_profile.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/community_links.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';

/// Lo que se sabe de cada comunidad (F44): su nombre con sus dos temas
/// principales, todos sus temas en orden, cuántos documentos y vínculos tiene,
/// con qué otras se une y cuál es su documento más nuevo.
///
/// El tema principal es el más unido con los DEMÁS de su comunidad —no el más
/// unido en total, que en un puente cuenta lo que lo une con otras—, y a igual
/// unión, el de más documentos. Si el segundo se llama igual que el primero
/// —dos «Roma» de ramas distintas—, el nombre usa el siguiente que no se
/// repita: «Roma · Roma» no le dice nada a nadie.
///
/// Recorre cada unión, cada asignación y cada vínculo una vez.
CommunityProfiles profileCommunities({
  required TopicGraph graph,
  required CommunityDetection detection,
  required TopicAdjacency adjacency,
  required CommunityLinks links,
  required TopicGraphInput input,
}) {
  final n = graph.nodes.length;
  final c = detection.communities.length;
  if (n == 0 || c == 0) return const CommunityProfiles.empty();
  final community = links.communityOfTopic;

  // Lo que une a cada tema con los demás de su comunidad.
  final internal = Float64List(n);
  for (var i = 0; i < n; i++) {
    for (var e = adjacency.offsets[i]; e < adjacency.offsets[i + 1]; e++) {
      if (community[adjacency.neighbors[e]] == community[i]) {
        internal[i] += adjacency.weights[e];
      }
    }
  }

  // Las comunidades de cada documento, sin repetir: para contarlo una vez en
  // cada una y para saber qué vínculos quedan adentro.
  final documents = Int32List(c);
  final latest = List<TopicItem?>.filled(c, null);
  final communitiesOf = HashMap<String, List<int>>();
  for (final item in input.items) {
    final mine = <int>[];
    for (final valueId in item.valueIds) {
      final position = graph.indexOf(valueId);
      if (position == null) continue;
      final at = community[position];
      if (!mine.contains(at)) mine.add(at);
    }
    if (mine.isEmpty) continue;
    communitiesOf[item.id] = mine;
    for (final at in mine) {
      documents[at]++;
      if (_isNewer(item, latest[at])) latest[at] = item;
    }
  }

  final internalLinks = Int32List(c);
  for (final relation in input.relations) {
    if (relation.fromItemId == relation.toItemId) continue;
    final from = communitiesOf[relation.fromItemId];
    final to = communitiesOf[relation.toItemId];
    if (from == null || to == null) continue;
    for (final at in from) {
      if (to.contains(at)) internalLinks[at]++;
    }
  }

  final profiles = <CommunityProfile>[];
  for (var at = 0; at < c; at++) {
    final found = detection.communities[at];
    final topics = [...found.members]
      ..sort((x, y) {
        final byInternal = internal[y].compareTo(internal[x]);
        if (byInternal != 0) return byInternal;
        final byItems = graph.nodes[y].itemCount.compareTo(
          graph.nodes[x].itemCount,
        );
        return byItems != 0 ? byItems : x.compareTo(y);
      });
    profiles.add(
      CommunityProfile(
        communityId: found.id,
        topics: topics,
        nameLabels: _nameOf(graph, topics),
        documentCount: documents[at],
        linkCount: internalLinks[at],
        neighbors: links.neighborsOf(found.id),
        latestItemId: latest[at]?.id,
      ),
    );
  }
  return CommunityProfiles(profiles, {
    for (var at = 0; at < c; at++) detection.communities[at].id: at,
  });
}

/// Los nombres de los primeros temas de [ranked] que no se repiten, como
/// mucho [kCommunityNameTopics].
List<String> _nameOf(TopicGraph graph, List<int> ranked) {
  final labels = <String>[];
  final seen = <String>{};
  for (final topic in ranked) {
    final label = graph.nodes[topic].label;
    if (!seen.add(normalizeVocabularyLabel(label))) continue;
    labels.add(label);
    if (labels.length == kCommunityNameTopics) break;
  }
  return labels;
}

/// Si [item] es más nuevo que [than]: por la fecha y, a igual fecha, por el
/// identificador, para que no dependa del orden en que llegaron. Lo que no
/// tiene fecha nunca es lo más nuevo.
bool _isNewer(TopicItem item, TopicItem? than) {
  final at = item.createdAt;
  if (at == null) return false;
  if (than == null) return true;
  final other = than.createdAt!;
  final byDate = at.compareTo(other);
  return byDate != 0 ? byDate > 0 : item.id.compareTo(than.id) > 0;
}
