import 'dart:typed_data';

import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// El tope de pasadas por los temas. La propagación converge en unas pocas;
/// el tope existe para que un grafo raro no la deje girando.
const kMaxCommunityPasses = 30;

/// Cuánto une a un tema con su padre en la jerarquía, sin que ningún elemento
/// lo diga: lo mismo que un elemento compartido. Sin esto, una rama del
/// vocabulario podría partirse en colores distintos solo porque nadie asignó
/// a la vez el padre y el hijo.
const kHierarchyWeight = 1.0;

/// Agrupa los temas de [graph] en comunidades por propagación de etiquetas
/// ponderada (F14, D1): cada tema adopta la etiqueta que más pesa entre sus
/// vecinos, hasta que ninguno cambia.
///
/// Es pura y DETERMINISTA: sin azar. Los temas se visitan en un orden que
/// sale de un hash de su valor —no de su posición, que cambia cuando aparece
/// un tema—, y un empate lo gana la etiqueta que el tema ya tiene o, si no
/// está entre las empatadas, la de menor identidad. El mismo grafo da siempre
/// las mismas comunidades.
///
/// Con [previous], el cálculo arranca en caliente: cada tema parte de su
/// comunidad anterior y solo se mueve lo que el cambio movió, normalmente en
/// una o dos pasadas. Las identidades de las comunidades que siguen existiendo
/// se conservan; lo que se parte o lo que nace recibe una nueva.
///
/// El peso de cada unión sale de [weights]; un tema se pega a su padre con
/// [hierarchyWeight]. Los temas sin ninguna unión quedan cada uno en su propia
/// comunidad, marcada como aislada.
CommunityDetection detectCommunities(
  TopicGraph graph, {
  TopicGraphWeights weights = const TopicGraphWeights(),
  double hierarchyWeight = kHierarchyWeight,
  CommunityMemory? previous,
  int maxPasses = kMaxCommunityPasses,
}) {
  final n = graph.nodes.length;
  final remembered = previous ?? const CommunityMemory.none();
  if (n == 0) return CommunityDetection.empty(remembered);

  final adjacency = _Adjacency.of(graph, weights, hierarchyWeight);

  // Las etiquetas de trabajo son índices densos —el `Float64List` de puntajes
  // no puede medir lo que llegó a valer la mayor identidad—: cada identidad
  // anterior es una, y cada tema sin pasado, la suya.
  final label = Int32List(n);
  final denseOf = <int, int>{};
  // La identidad de cada etiqueta, o -1 si es de un tema sin pasado.
  final identityOf = <int>[];
  for (var i = 0; i < n; i++) {
    final known = remembered.byValueId[graph.nodes[i].valueId];
    if (known == null) {
      label[i] = identityOf.length;
      identityOf.add(-1);
    } else {
      label[i] = denseOf.putIfAbsent(known, () {
        identityOf.add(known);
        return identityOf.length - 1;
      });
    }
  }
  // Para desempatar: las identidades anteriores, por su número; las nuevas,
  // después y por su posición.
  final tieKey = List<int>.generate(
    identityOf.length,
    (l) => identityOf[l] >= 0 ? identityOf[l] : (1 << 40) + l,
  );

  final order = _visitOrder(graph);
  final score = Float64List(identityOf.length);
  final touched = Int32List(identityOf.length);

  var passes = 0;
  var changed = true;
  while (changed && passes < maxPasses) {
    changed = false;
    passes++;
    for (final i in order) {
      final start = adjacency.offsets[i];
      final end = adjacency.offsets[i + 1];
      // Sin uniones, se queda con la etiqueta que tiene.
      if (start == end) continue;

      var touchedCount = 0;
      for (var e = start; e < end; e++) {
        final l = label[adjacency.neighbors[e]];
        if (score[l] == 0) touched[touchedCount++] = l;
        score[l] += adjacency.weights[e];
      }

      final current = label[i];
      var best = -1;
      var bestScore = 0.0;
      for (var t = 0; t < touchedCount; t++) {
        final l = touched[t];
        final s = score[l];
        if (s > bestScore) {
          best = l;
          bestScore = s;
        } else if (s == bestScore) {
          // Empate: gana la etiqueta actual y, si no está, la de menor clave.
          if (l == current) {
            best = l;
          } else if (best != current && tieKey[l] < tieKey[best]) {
            best = l;
          }
        }
      }
      for (var t = 0; t < touchedCount; t++) {
        score[touched[t]] = 0;
      }
      if (best != current) {
        label[i] = best;
        changed = true;
      }
    }
  }

  return _finish(
    graph: graph,
    adjacency: adjacency,
    label: label,
    identityOf: identityOf,
    remembered: remembered,
    passes: passes,
    converged: !changed,
  );
}

/// Las uniones del grafo en forma de listas por tema: `neighbors` y `weights`
/// desde `offsets[i]` hasta `offsets[i + 1]` son las del tema `i`. Una unión
/// aparece en las listas de sus dos temas.
class _Adjacency {
  _Adjacency(this.offsets, this.neighbors, this.weights);

  factory _Adjacency.of(
    TopicGraph graph,
    TopicGraphWeights weights,
    double hierarchyWeight,
  ) {
    final n = graph.nodes.length;
    final a = <int>[];
    final b = <int>[];
    final w = <double>[];
    for (final edge in graph.edges) {
      final weight = weights.of(edge);
      if (weight <= 0) continue;
      a.add(edge.a);
      b.add(edge.b);
      w.add(weight);
    }
    if (hierarchyWeight > 0) {
      for (var i = 0; i < n; i++) {
        final parentId = graph.nodes[i].parentId;
        final parent = parentId == null ? null : graph.indexOf(parentId);
        if (parent == null || parent == i) continue;
        a.add(i);
        b.add(parent);
        w.add(hierarchyWeight);
      }
    }

    final offsets = Int32List(n + 1);
    for (var k = 0; k < a.length; k++) {
      offsets[a[k] + 1]++;
      offsets[b[k] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      offsets[i + 1] += offsets[i];
    }
    final neighbors = Int32List(offsets[n]);
    final edgeWeights = Float64List(offsets[n]);
    final cursor = Int32List.fromList(offsets);
    for (var k = 0; k < a.length; k++) {
      neighbors[cursor[a[k]]] = b[k];
      edgeWeights[cursor[a[k]]++] = w[k];
      neighbors[cursor[b[k]]] = a[k];
      edgeWeights[cursor[b[k]]++] = w[k];
    }
    return _Adjacency(offsets, neighbors, edgeWeights);
  }

  final Int32List offsets;
  final Int32List neighbors;
  final Float64List weights;

  int degreeOf(int i) => offsets[i + 1] - offsets[i];

  double weightOf(int i) {
    var total = 0.0;
    for (var e = offsets[i]; e < offsets[i + 1]; e++) {
      total += weights[e];
    }
    return total;
  }
}

/// El orden en que se visitan los temas: por un hash de su valor con una
/// semilla fija, y a igual hash por posición. No depende de qué posición ocupa
/// cada tema, así que agregar un tema no reordena a los demás.
List<int> _visitOrder(TopicGraph graph) {
  final n = graph.nodes.length;
  final keys = Uint32List(n);
  for (var i = 0; i < n; i++) {
    // FNV-1a de 32 bits sobre las unidades del identificador.
    var hash = 0x811c9dc5 ^ 0x5eed;
    for (final unit in graph.nodes[i].valueId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    keys[i] = hash;
  }
  return List<int>.generate(n, (i) => i)..sort((x, y) {
    final byKey = keys[x].compareTo(keys[y]);
    return byKey != 0 ? byKey : x.compareTo(y);
  });
}

/// Cierra el cálculo: parte cada etiqueta en sus componentes conexos —la
/// propagación puede dejar una etiqueta repartida en dos zonas sin unión—,
/// decide qué identidad lleva cada comunidad y arma el resultado.
CommunityDetection _finish({
  required TopicGraph graph,
  required _Adjacency adjacency,
  required Int32List label,
  required List<int> identityOf,
  required CommunityMemory remembered,
  required int passes,
  required bool converged,
}) {
  final n = graph.nodes.length;

  // Componentes conexos de cada etiqueta, en orden de posición: el primer tema
  // que se encuentra de un componente es el de menor posición.
  final component = Int32List(n)..fillRange(0, n, -1);
  final members = <List<int>>[];
  final stack = <int>[];
  for (var start = 0; start < n; start++) {
    if (component[start] != -1) continue;
    final id = members.length;
    final found = <int>[];
    component[start] = id;
    stack.add(start);
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      found.add(node);
      for (
        var e = adjacency.offsets[node];
        e < adjacency.offsets[node + 1];
        e++
      ) {
        final next = adjacency.neighbors[e];
        if (component[next] == -1 && label[next] == label[start]) {
          component[next] = id;
          stack.add(next);
        }
      }
    }
    members.add(found..sort());
  }

  // Cada identidad anterior la conserva el componente más grande que la lleva;
  // los demás, y los de etiquetas sin pasado, reciben identidades nuevas.
  int bySizeThenPosition(int x, int y) {
    final bySize = members[y].length.compareTo(members[x].length);
    return bySize != 0 ? bySize : members[x].first.compareTo(members[y].first);
  }

  final ordered = List<int>.generate(members.length, (i) => i)
    ..sort(bySizeThenPosition);
  final idOfComponent = List<int>.filled(members.length, -1);
  final taken = <int>{};
  for (final c in ordered) {
    final identity = identityOf[label[members[c].first]];
    if (identity >= 0 && taken.add(identity)) idOfComponent[c] = identity;
  }
  var nextId = remembered.nextId;
  for (final c in ordered) {
    if (idOfComponent[c] == -1) idOfComponent[c] = nextId++;
  }

  final communityOf = Int32List(n);
  for (var c = 0; c < members.length; c++) {
    for (final node in members[c]) {
      communityOf[node] = idOfComponent[c];
    }
  }

  var reassigned = 0;
  for (var i = 0; i < n; i++) {
    final before = remembered.byValueId[graph.nodes[i].valueId];
    if (before != null && before != communityOf[i]) reassigned++;
  }

  final communities = <TopicCommunity>[
    for (final c in ordered)
      _communityOf(idOfComponent[c], members[c], adjacency),
  ];

  return CommunityDetection(
    communityOf: communityOf,
    communities: communities,
    memory: CommunityMemory(
      byValueId: {
        for (var i = 0; i < n; i++) graph.nodes[i].valueId: communityOf[i],
      },
      nextId: nextId,
    ),
    passes: passes,
    converged: converged,
    reassigned: reassigned,
  );
}

TopicCommunity _communityOf(int id, List<int> members, _Adjacency adjacency) {
  var anchor = members.first;
  var anchorWeight = -1.0;
  for (final node in members) {
    final weight = adjacency.weightOf(node);
    if (weight > anchorWeight) {
      anchor = node;
      anchorWeight = weight;
    }
  }
  return TopicCommunity(
    id: id,
    members: members,
    anchor: anchor,
    isIsolated: members.length == 1 && adjacency.degreeOf(members.first) == 0,
  );
}
