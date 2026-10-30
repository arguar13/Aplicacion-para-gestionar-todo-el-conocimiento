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
TopicGraph buildTopicGraph(TopicGraphInput input) =>
    _buildTopicGraph(input, null).current;

/// Un grafo de temas y el mismo grafo como era en [asOf] (F44).
class TopicGraphHistory {
  const TopicGraphHistory({
    required this.current,
    required this.past,
    required this.asOf,
    required this.changedSince,
  });

  /// El grafo de hoy: el mismo que da [buildTopicGraph].
  final TopicGraph current;

  /// El grafo como era en [asOf], armado con lo que la base todavía tiene:
  /// los temas creados antes y las uniones que ya tenían algo que las
  /// sostuviera, con lo que contaban entonces. Sus posiciones son propias:
  /// para pasar de uno al otro se usa el valor. Lo que se borró después no
  /// está en la base y no se puede contar: es el grafo de lo que sigue vivo.
  final TopicGraph past;

  final DateTime asOf;

  /// Si algo del grafo es de [asOf] en adelante. Si no, [past] es [current],
  /// el mismo objeto: no hay nada que volver a agrupar.
  final bool changedSince;
}

/// [buildTopicGraph] y, en la MISMA pasada, el grafo como era en [asOf]: lo
/// que hace falta para decir cuántas comunidades había hace un mes (F44) sin
/// volver a contar cada par de temas.
///
/// Un tema existía si su valor se creó antes de [asOf]; una coincidencia, si
/// el elemento se procesó antes; una relación, si se vinculó antes y sus dos
/// extremos ya estaban. Lo que no tiene fecha cuenta como de siempre.
TopicGraphHistory buildTopicGraphHistory(
  TopicGraphInput input, {
  required DateTime asOf,
}) => _buildTopicGraph(input, asOf);

TopicGraphHistory _buildTopicGraph(TopicGraphInput input, DateTime? asOf) {
  final values = input.values;
  if (values.isEmpty) {
    final empty = TopicGraph.empty(
      input.definitionId,
      name: input.definitionName,
    );
    return TopicGraphHistory(
      current: empty,
      past: empty,
      asOf: asOf ?? DateTime.fromMillisecondsSinceEpoch(0),
      changedSince: false,
    );
  }

  /// Si [at] es de antes de [asOf]: lo que no tiene fecha, sí.
  bool before(DateTime? at) => asOf == null || at == null || at.isBefore(asOf);

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
  final itemCountBefore = Int32List(count);
  var changedSince = false;

  // Los temas de cada elemento, por posición, sin repetir y ordenados.
  final topicsOfItem = HashMap<String, List<int>>();
  // Los elementos procesados de [asOf] en adelante: solo con [asOf].
  final newItems = HashSet<String>();
  for (final item in input.items) {
    final positions = <int>{};
    for (final valueId in item.valueIds) {
      final position = indexOf[valueId];
      if (position != null) positions.add(position);
    }
    if (positions.isEmpty) continue;
    final old = before(item.createdAt);
    if (!old) {
      newItems.add(item.id);
      changedSince = true;
    }
    final sorted = positions.toList()..sort();
    for (final position in sorted) {
      itemCount[position]++;
      if (old) itemCountBefore[position]++;
    }
    topicsOfItem[item.id] = sorted.length > kMaxTopicsPerItem
        ? sorted.sublist(0, kMaxTopicsPerItem)
        : sorted;
  }

  // Un acumulador por par de temas, con la clave a * count + b y a < b.
  final tally = _PairTally(count);

  for (final MapEntry(key: id, value: positions) in topicsOfItem.entries) {
    final old = !newItems.contains(id);
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        final s = tally.slot(positions[i], positions[j]);
        tally.cooccurrence[s]++;
        if (old) tally.cooccurrenceBefore[s]++;
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
    final old =
        before(relation.createdAt) &&
        !newItems.contains(relation.fromItemId) &&
        !newItems.contains(relation.toItemId);
    if (!old) changedSince = true;
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
          if (old) {
            tally.contradictionsBefore[s]++;
            if (!relation.reviewed) tally.openBefore[s]++;
          }
        } else {
          tally.related[s]++;
          if (old) tally.relatedBefore[s]++;
        }
      }
    }
  }

  final current = TopicGraph(
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
  if (asOf == null) {
    return TopicGraphHistory(
      current: current,
      past: current,
      asOf: DateTime.fromMillisecondsSinceEpoch(0),
      changedSince: false,
    );
  }

  // Los temas de entonces, con su posición en el grafo de entonces.
  final pastPosition = Int32List(count)..fillRange(0, count, -1);
  var pastCount = 0;
  for (var i = 0; i < count; i++) {
    if (before(input.valueCreatedAt[ordered[i].id])) {
      pastPosition[i] = pastCount++;
    } else {
      changedSince = true;
    }
  }
  if (!changedSince) {
    return TopicGraphHistory(
      current: current,
      past: current,
      asOf: asOf,
      changedSince: false,
    );
  }

  return TopicGraphHistory(
    current: current,
    past: TopicGraph(
      definitionId: input.definitionId,
      definitionName: input.definitionName,
      nodes: [
        for (var i = 0; i < count; i++)
          if (pastPosition[i] != -1)
            TopicNode(
              valueId: current.nodes[i].valueId,
              label: current.nodes[i].label,
              parentId: current.nodes[i].parentId,
              depth: current.nodes[i].depth,
              itemCount: itemCountBefore[i],
            ),
      ],
      edges: tally.edgesBefore(pastPosition),
    ),
    asOf: asOf,
    changedSince: true,
  );
}

/// Lo que se cuenta de cada par de temas, con una posición por par: todo, y
/// aparte lo que ya existía en la fecha que se pidió (F44).
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
  final cooccurrenceBefore = <int>[];
  final relatedBefore = <int>[];
  final contradictionsBefore = <int>[];
  final openBefore = <int>[];

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
      cooccurrenceBefore.add(0);
      relatedBefore.add(0);
      contradictionsBefore.add(0);
      openBefore.add(0);
      lastRelation.add(0);
      return cooccurrence.length - 1;
    });
  }

  /// Los pares por sus extremos.
  List<int> _order() => List<int>.generate(cooccurrence.length, (i) => i)
    ..sort((x, y) {
      final byLow = _ends[2 * x].compareTo(_ends[2 * y]);
      return byLow != 0 ? byLow : _ends[2 * x + 1].compareTo(_ends[2 * y + 1]);
    });

  List<TopicEdge> edges() => [
    for (final e in _order())
      TopicEdge(
        a: _ends[2 * e],
        b: _ends[2 * e + 1],
        cooccurrence: cooccurrence[e],
        relations: related[e],
        contradictions: contradictions[e],
        openContradictions: open[e],
      ),
  ];

  /// Las uniones que ya existían, con lo que contaban entonces, entre temas
  /// que ya existían: [position] da la posición de cada tema en el grafo de
  /// entonces, o -1 si todavía no estaba. Como las posiciones de entonces
  /// conservan el orden de las de hoy, el orden por extremos se conserva.
  List<TopicEdge> edgesBefore(Int32List position) => [
    for (final e in _order())
      if (position[_ends[2 * e]] != -1 &&
          position[_ends[2 * e + 1]] != -1 &&
          cooccurrenceBefore[e] + relatedBefore[e] + contradictionsBefore[e] >
              0)
        TopicEdge(
          a: position[_ends[2 * e]],
          b: position[_ends[2 * e + 1]],
          cooccurrence: cooccurrenceBefore[e],
          relations: relatedBefore[e],
          contradictions: contradictionsBefore[e],
          openContradictions: openBefore[e],
        ),
  ];
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
