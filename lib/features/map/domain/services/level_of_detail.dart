import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Cuántos nodos dibuja el mapa a la vez, como máximo, alejado: comunidades.
const kMaxOverviewNodes = 60;

/// Cuántos temas dibuja el mapa a la vez, como máximo, a distancia media.
const kMaxVisibleTopics = 300;

/// Qué es un nodo del panorama.
enum OverviewKind {
  /// Una comunidad de temas.
  community,

  /// Varias comunidades chicas juntas, porque no entran todas.
  overflow,

  /// Los temas sin ninguna unión, juntos.
  isolated,
}

/// Un nodo del panorama alejado (F14, D5): una comunidad de temas, o varias
/// que no entran, o los temas aislados.
class OverviewNode {
  const OverviewNode({
    required this.kind,
    required this.communityIds,
    required this.members,
    required this.anchor,
    required this.itemCount,
    required this.internalWeight,
  });

  final OverviewKind kind;

  /// Las identidades de las comunidades que junta: una para
  /// [OverviewKind.community]; varias en los otros dos casos.
  final List<int> communityIds;

  /// Las posiciones en `TopicGraph.nodes` de todos sus temas, de menor a mayor.
  final List<int> members;

  /// La posición del tema que lo nombra, o `null` si junta varias comunidades.
  final int? anchor;

  /// Cuántas asignaciones de elementos suman sus temas. Un elemento en dos
  /// temas cuenta dos veces: es el tamaño del nodo, no un recuento de
  /// elementos.
  final int itemCount;

  /// Lo que suman las uniones entre sus propios temas.
  final double internalWeight;

  int get topicCount => members.length;
}

/// La unión entre dos nodos del panorama, con lo que suman las uniones entre
/// sus temas.
class OverviewEdge {
  const OverviewEdge({
    required this.a,
    required this.b,
    required this.weight,
    required this.hasTension,
  });

  /// Posiciones en `CommunityOverview.nodes`, con `a < b`.
  final int a;
  final int b;
  final double weight;

  /// Si alguna de las uniones que junta es una contradicción.
  final bool hasTension;
}

/// El mapa visto de lejos: las comunidades como nodos.
class CommunityOverview {
  const CommunityOverview({required this.nodes, required this.edges});

  final List<OverviewNode> nodes;
  final List<OverviewEdge> edges;
}

/// Junta el grafo de temas en sus comunidades, para dibujar unas decenas de
/// nodos y no miles (F14, D5).
///
/// Las comunidades más grandes son un nodo cada una. Los temas aislados, que
/// no tienen nada que decir de a uno, van juntos en un único nodo; y si las
/// comunidades con uniones son más de las que entran en [maxNodes], las más
/// chicas se juntan en otro. Como mucho hay [maxNodes] nodos, y nunca menos de
/// tres de lugar: una comunidad, el desborde y los aislados.
CommunityOverview aggregateCommunities(
  TopicGraph graph,
  CommunityDetection detection, {
  TopicGraphWeights weights = const TopicGraphWeights(),
  int maxNodes = kMaxOverviewNodes,
}) {
  final connected = [
    for (final c in detection.communities)
      if (!c.isIsolated) c,
  ];
  final isolated = [
    for (final c in detection.communities)
      if (c.isIsolated) c,
  ];

  // Los nodos de comunidad que caben: el lugar del nodo de aislados, si lo
  // hay, y el del de desborde, si hace falta.
  var room = (maxNodes < 3 ? 3 : maxNodes) - (isolated.isEmpty ? 0 : 1);
  var overflowing = <TopicCommunity>[];
  var shown = connected;
  if (connected.length > room) {
    room -= 1;
    shown = connected.sublist(0, room);
    overflowing = connected.sublist(room);
  }

  final nodeOfTopic = Int32List(graph.nodes.length);
  final drafts = <_Draft>[];

  void add(OverviewKind kind, List<TopicCommunity> communities, {int? anchor}) {
    final index = drafts.length;
    final members = [for (final c in communities) ...c.members]..sort();
    var items = 0;
    for (final topic in members) {
      nodeOfTopic[topic] = index;
      items += graph.nodes[topic].itemCount;
    }
    drafts.add(
      _Draft(
        kind: kind,
        communityIds: [for (final c in communities) c.id],
        members: members,
        anchor: anchor,
        itemCount: items,
      ),
    );
  }

  for (final community in shown) {
    add(OverviewKind.community, [community], anchor: community.anchor);
  }
  if (overflowing.isNotEmpty) add(OverviewKind.overflow, overflowing);
  if (isolated.isNotEmpty) add(OverviewKind.isolated, isolated);

  // Lo que une a los nodos entre sí y lo que suma cada uno por dentro.
  final internal = List<double>.filled(drafts.length, 0);
  final between = <int, ({double weight, bool tension})>{};
  for (final edge in graph.edges) {
    final weight = weights.of(edge);
    if (weight <= 0) continue;
    final a = nodeOfTopic[edge.a];
    final b = nodeOfTopic[edge.b];
    if (a == b) {
      internal[a] += weight;
      continue;
    }
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    final key = low * drafts.length + high;
    final before = between[key];
    between[key] = (
      weight: (before?.weight ?? 0) + weight,
      tension: (before?.tension ?? false) || edge.isTension,
    );
  }

  final keys = between.keys.toList()..sort();
  return CommunityOverview(
    nodes: [
      for (var i = 0; i < drafts.length; i++)
        OverviewNode(
          kind: drafts[i].kind,
          communityIds: drafts[i].communityIds,
          members: drafts[i].members,
          anchor: drafts[i].anchor,
          itemCount: drafts[i].itemCount,
          internalWeight: internal[i],
        ),
    ],
    edges: [
      for (final key in keys)
        OverviewEdge(
          a: key ~/ drafts.length,
          b: key % drafts.length,
          weight: between[key]!.weight,
          hasTension: between[key]!.tension,
        ),
    ],
  );
}

/// Un nodo del panorama a medio armar: falta lo que suman sus uniones internas.
class _Draft {
  const _Draft({
    required this.kind,
    required this.communityIds,
    required this.members,
    required this.anchor,
    required this.itemCount,
  });

  final OverviewKind kind;
  final List<int> communityIds;
  final List<int> members;
  final int? anchor;
  final int itemCount;
}

/// Cuánto une cada tema con los demás: la suma de los pesos de sus uniones.
Float64List topicStrength(TopicGraph graph, TopicGraphWeights weights) {
  final strength = Float64List(graph.nodes.length);
  for (final edge in graph.edges) {
    final weight = weights.of(edge);
    strength[edge.a] += weight;
    strength[edge.b] += weight;
  }
  return strength;
}

/// Los temas que se dibujan a distancia media, y las uniones entre ellos.
class TopicSelection {
  const TopicSelection({
    required this.topics,
    required this.edges,
    required this.hidden,
  });

  /// Posiciones en `TopicGraph.nodes`, de menor a mayor.
  final List<int> topics;

  /// Posiciones en `TopicGraph.edges` de las uniones con los DOS extremos
  /// dentro de [topics].
  final List<int> edges;

  /// Cuántos temas del grafo quedaron sin dibujar.
  final int hidden;
}

/// Elige hasta [limit] temas para dibujar (F14, D5): el layout de fuerzas
/// cuesta el cuadrado de los nodos, y dibujar 2.000 legibles en un celular no
/// es el objetivo.
///
/// Sin [focus], los más importantes: los que más unen y más elementos tienen.
/// Con [focus], los del foco y, desde ahí, los que más los unen a los ya
/// elegidos, uno por uno: un vecindario que crece por donde más peso hay. Si
/// el foco se agota —la parte conexa era chica—, se completa con los más
/// importantes del resto. El resultado no depende del orden en que vengan los
/// temas.
TopicSelection selectTopics(
  TopicGraph graph, {
  TopicGraphWeights weights = const TopicGraphWeights(),
  Set<int> focus = const {},
  int limit = kMaxVisibleTopics,
}) {
  final n = graph.nodes.length;
  final strength = topicStrength(graph, weights);

  List<int> chosen;
  if (n <= limit) {
    chosen = List<int>.generate(n, (i) => i);
  } else {
    final importance = Float64List(n);
    for (var i = 0; i < n; i++) {
      importance[i] = strength[i] + graph.nodes[i].itemCount;
    }
    final byImportance = List<int>.generate(n, (i) => i)
      ..sort((x, y) {
        final byScore = importance[y].compareTo(importance[x]);
        return byScore != 0 ? byScore : x.compareTo(y);
      });

    if (focus.isEmpty) {
      chosen = byImportance.sublist(0, limit);
    } else {
      chosen = _grow(graph, weights, focus, byImportance, limit);
    }
  }
  chosen.sort();

  final inside = Uint8List(n);
  for (final topic in chosen) {
    inside[topic] = 1;
  }
  return TopicSelection(
    topics: chosen,
    edges: [
      for (var e = 0; e < graph.edges.length; e++)
        if (inside[graph.edges[e].a] == 1 && inside[graph.edges[e].b] == 1) e,
    ],
    hidden: n - chosen.length,
  );
}

/// El vecindario de [focus]: cada paso suma el tema con más peso hacia lo ya
/// elegido, desempatando por posición.
List<int> _grow(
  TopicGraph graph,
  TopicGraphWeights weights,
  Set<int> focus,
  List<int> byImportance,
  int limit,
) {
  final n = graph.nodes.length;
  final neighbors = List.generate(n, (_) => <int>[]);
  final edgeWeight = <double>[];
  for (var e = 0; e < graph.edges.length; e++) {
    final edge = graph.edges[e];
    edgeWeight.add(weights.of(edge));
    neighbors[edge.a].add(e);
    neighbors[edge.b].add(e);
  }

  final selected = Uint8List(n);
  final affinity = Float64List(n);
  final chosen = <int>[];

  void take(int topic) {
    selected[topic] = 1;
    chosen.add(topic);
    for (final e in neighbors[topic]) {
      final edge = graph.edges[e];
      final other = edge.a == topic ? edge.b : edge.a;
      if (selected[other] == 0) affinity[other] += edgeWeight[e];
    }
  }

  final ordered = focus.where((t) => t >= 0 && t < n).toList()..sort();
  for (final topic in ordered) {
    if (chosen.length < limit) take(topic);
  }

  var fallback = 0;
  while (chosen.length < limit) {
    var best = -1;
    var bestAffinity = 0.0;
    for (var i = 0; i < n; i++) {
      if (selected[i] == 0 && affinity[i] > bestAffinity) {
        best = i;
        bestAffinity = affinity[i];
      }
    }
    if (best == -1) {
      // Nada más conectado con lo elegido: los más importantes que falten.
      while (fallback < byImportance.length &&
          selected[byImportance[fallback]] == 1) {
        fallback++;
      }
      if (fallback == byImportance.length) break;
      best = byImportance[fallback];
    }
    take(best);
  }
  return chosen;
}

/// El vecindario de [focus] para el nivel de temas del grafo (F14, D5): los
/// temas del foco y los que se unen directamente a alguno, hasta [limit].
///
/// A diferencia de [selectTopics], no crece por más saltos ni se completa con
/// lo más importante del resto: al acercarse a una comunidad se ve ella y lo
/// que la toca, no toda la bóveda. Si el foco solo ya pasa el tope, entran los
/// más importantes de él; si sobra lugar, los vecinos que más los unen.
/// `hidden` cuenta lo que el foco y sus vecinos tenían de más.
TopicSelection selectNeighborhood(
  TopicGraph graph, {
  required Set<int> focus,
  TopicGraphWeights weights = const TopicGraphWeights(),
  int limit = kMaxVisibleTopics,
}) {
  final n = graph.nodes.length;
  final valid = focus.where((t) => t >= 0 && t < n).toList()..sort();
  final inFocus = Uint8List(n);
  for (final topic in valid) {
    inFocus[topic] = 1;
  }

  final strength = topicStrength(graph, weights);
  final byImportance = [...valid]
    ..sort((x, y) {
      final byScore = (strength[y] + graph.nodes[y].itemCount).compareTo(
        strength[x] + graph.nodes[x].itemCount,
      );
      return byScore != 0 ? byScore : x.compareTo(y);
    });
  final chosen = <int>[...byImportance.take(limit)];

  // Los vecinos, por cuánto los une con el foco.
  final affinity = Float64List(n);
  for (final edge in graph.edges) {
    final weight = weights.of(edge);
    if (inFocus[edge.a] == 1 && inFocus[edge.b] == 0) {
      affinity[edge.b] += weight;
    } else if (inFocus[edge.b] == 1 && inFocus[edge.a] == 0) {
      affinity[edge.a] += weight;
    }
  }
  final neighbors =
      [
        for (var i = 0; i < n; i++)
          if (affinity[i] > 0) i,
      ]..sort((x, y) {
        final byAffinity = affinity[y].compareTo(affinity[x]);
        return byAffinity != 0 ? byAffinity : x.compareTo(y);
      });
  final room = limit - chosen.length;
  if (room > 0) chosen.addAll(neighbors.take(room));

  chosen.sort();
  final inside = Uint8List(n);
  for (final topic in chosen) {
    inside[topic] = 1;
  }
  return TopicSelection(
    topics: chosen,
    edges: [
      for (var e = 0; e < graph.edges.length; e++)
        if (inside[graph.edges[e].a] == 1 && inside[graph.edges[e].b] == 1) e,
    ],
    hidden: valid.length + neighbors.length - chosen.length,
  );
}
