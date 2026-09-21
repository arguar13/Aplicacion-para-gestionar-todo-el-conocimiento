import 'dart:collection';
import 'dart:typed_data';

import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart'
    show AtlasValueRow;
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Cuántos temas de UN elemento se tienen en cuenta, como mucho, para saber
/// qué temas aparecen juntos. Cada par de temas de un elemento es una
/// coincidencia, así que el costo crece con el cuadrado: un elemento con
/// cincuenta temas daría más de mil pares y no le dice nada nuevo a nadie. Se
/// quedan los primeros por orden alfabético: el recorte no depende de cómo la
/// base entregó los valores.
const kMaxTopicsPerItem = 40;

/// Arma el grafo de temas de una categoría (F14) con lo que la base contó.
///
/// Es puro: la base entrega filas, y acá se cuenta. Un par de temas gana una
/// arista si aparecen juntos en un elemento o si alguna relación une un
/// elemento de uno con un elemento del otro; una relación entre elementos que
/// comparten un tema no crea una arista de ese tema consigo mismo, y una
/// relación cuenta UNA vez por par de temas aunque sus dos extremos tengan
/// varios.
///
/// Solo cuentan los elementos de [TopicGraphInput.items] y las relaciones con
/// sus DOS extremos ahí: lo que está en la papelera o lo que el filtro dejó
/// afuera no aporta una arista con la mitad de sus extremos.
TopicGraph buildTopicGraph(TopicGraphInput input) {
  final values = input.values;
  if (values.isEmpty) {
    return TopicGraph.empty(input.definitionId, name: input.definitionName);
  }

  // El nombre sin acentos ni mayúsculas, UNA vez: normalizar dentro de un
  // comparador lo repite en cada comparación.
  final keyOf = {
    for (final value in values) value.id: normalizeVocabularyLabel(value.label),
  };
  final ordered = [...values]
    ..sort((x, y) {
      final byLabel = keyOf[x.id]!.compareTo(keyOf[y.id]!);
      return byLabel != 0 ? byLabel : x.id.compareTo(y.id);
    });
  final count = ordered.length;
  final indexOf = {for (var i = 0; i < count; i++) ordered[i].id: i};

  final hierarchy = _hierarchy(ordered, indexOf);
  final itemCount = Int32List(count);

  // Los temas de cada elemento, por posición, sin repetir y ordenados.
  final topicsOfItem = HashMap<String, List<int>>();
  for (final item in input.items) {
    final positions = <int>{};
    for (final valueId in item.valueIds) {
      final position = indexOf[valueId];
      if (position != null) positions.add(position);
    }
    if (positions.isEmpty) continue;
    final sorted = positions.toList()..sort();
    for (final position in sorted) {
      itemCount[position]++;
    }
    topicsOfItem[item.id] = sorted.length > kMaxTopicsPerItem
        ? sorted.sublist(0, kMaxTopicsPerItem)
        : sorted;
  }

  // Un acumulador por par de temas, con la clave a * count + b y a < b.
  final tally = _PairTally(count);

  for (final positions in topicsOfItem.values) {
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        tally.cooccurrence[tally.slot(positions[i], positions[j])]++;
      }
    }
  }

  var relationNumber = 0;
  for (final relation in input.relations) {
    final from = topicsOfItem[relation.fromItemId];
    final to = topicsOfItem[relation.toItemId];
    if (from == null || to == null) continue;
    relationNumber++;
    final isContradiction = relation.kind == RelationKind.contradicts;
    for (final a in from) {
      for (final b in to) {
        if (a == b) continue;
        final s = tally.slot(a, b);
        // Una relación cuenta una vez por par de temas: (A, B) y (B, A) son
        // el mismo par.
        if (tally.lastRelation[s] == relationNumber) continue;
        tally.lastRelation[s] = relationNumber;
        if (isContradiction) {
          tally.contradictions[s]++;
          if (!relation.reviewed) tally.open[s]++;
        } else {
          tally.related[s]++;
        }
      }
    }
  }

  return TopicGraph(
    definitionId: input.definitionId,
    definitionName: input.definitionName,
    nodes: [
      for (var i = 0; i < count; i++)
        TopicNode(
          valueId: ordered[i].id,
          label: ordered[i].label,
          parentId: hierarchy.parentOf[i] == -1
              ? null
              : ordered[hierarchy.parentOf[i]].id,
          depth: hierarchy.depth[i],
          itemCount: itemCount[i],
        ),
    ],
    edges: tally.edges(),
  );
}

/// Lo que se cuenta de cada par de temas, con una posición por par.
///
/// Los pares nacen en el orden en que se ven, que depende de cómo la base
/// entregó los elementos; [edges] los entrega ordenados por sus extremos, para
/// que el mismo contenido dé siempre el mismo grafo.
class _PairTally {
  _PairTally(this._count);

  final int _count;
  final _slotOf = HashMap<int, int>();
  final _ends = <int>[];
  final cooccurrence = <int>[];
  final related = <int>[];
  final contradictions = <int>[];
  final open = <int>[];

  /// La última relación que sumó a cada par, para no sumar dos veces la misma.
  final lastRelation = <int>[];

  int slot(int a, int b) {
    final low = a < b ? a : b;
    final high = a < b ? b : a;
    return _slotOf.putIfAbsent(low * _count + high, () {
      _ends
        ..add(low)
        ..add(high);
      cooccurrence.add(0);
      related.add(0);
      contradictions.add(0);
      open.add(0);
      lastRelation.add(0);
      return cooccurrence.length - 1;
    });
  }

  List<TopicEdge> edges() {
    final order = List<int>.generate(cooccurrence.length, (i) => i)
      ..sort((x, y) {
        final byLow = _ends[2 * x].compareTo(_ends[2 * y]);
        return byLow != 0
            ? byLow
            : _ends[2 * x + 1].compareTo(_ends[2 * y + 1]);
      });
    return [
      for (final e in order)
        TopicEdge(
          a: _ends[2 * e],
          b: _ends[2 * e + 1],
          cooccurrence: cooccurrence[e],
          relations: related[e],
          contradictions: contradictions[e],
          openContradictions: open[e],
        ),
    ];
  }
}

/// El padre y el nivel de cada valor, por posición. Un padre que no está entre
/// los valores deja al hijo en la raíz; el nivel se recorre hacia arriba y un
/// ciclo dañado —que la base no admite— no cuelga el recorrido.
({Int32List parentOf, Int32List depth}) _hierarchy(
  List<AtlasValueRow> ordered,
  Map<String, int> indexOf,
) {
  final count = ordered.length;
  final parentOf = Int32List(count)..fillRange(0, count, -1);
  for (var i = 0; i < count; i++) {
    final parentId = ordered[i].parentId;
    if (parentId != null) parentOf[i] = indexOf[parentId] ?? -1;
  }
  final depth = Int32List(count);
  for (var i = 0; i < count; i++) {
    var level = 0;
    var node = parentOf[i];
    // Nunca más de `count` saltos: una jerarquía con un ciclo termina.
    while (node != -1 && level <= count) {
      level++;
      node = parentOf[node];
    }
    depth[i] = level;
  }
  return (parentOf: parentOf, depth: depth);
}
