import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/ai_organize/domain/services/text_parts.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';

/// De a cuántos ids se pregunta por los vectores de un conjunto: lejos del
/// tope de variables de SQLite.
const _idsPerQuery = 500;

/// [ItemVectorIndex] contra `AppDatabase` (F30).
///
/// Lee los vectores sin decodificar y hace las cuentas fuera del hilo de la
/// interfaz (`compute`), como `RelationCandidateSelectorImpl`: diez libros son
/// diez mil vectores, y decodificarlos en el hilo de la pantalla la traba.
class ItemVectorIndexImpl implements ItemVectorIndex {
  const ItemVectorIndexImpl({required AppDatabase database}) : _db = database;

  final AppDatabase _db;

  @override
  Future<List<ItemSimilarity>> nearestTo(
    List<double> query, {
    required int limit,
    required double minSimilarity,
  }) async {
    if (query.isEmpty || limit <= 0) return const [];
    final vectors = await _vectorsByItem();
    if (vectors.isEmpty) return const [];
    final scores = await compute(_bestPerItem, (
      query: query,
      vectors: vectors,
      minSimilarity: minSimilarity,
    ));
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in ranked.take(limit))
        ItemSimilarity(itemId: entry.key, score: entry.value),
    ];
  }

  @override
  Future<List<String>> representativeOrder(
    List<String> itemIds, {
    required int take,
  }) async {
    final ids = <String>[];
    final seen = <String>{};
    for (final id in itemIds) {
      if (seen.add(id)) ids.add(id);
    }
    if (ids.length <= 1 || take <= 0) return ids;

    final vectors = await _vectorsByItem(only: ids);
    final withVectors = [
      for (final id in ids)
        if (vectors.containsKey(id)) id,
    ];
    final picked = withVectors.length <= 1
        ? withVectors
        : await compute(_farthestPointOrder, (
            ids: withVectors,
            vectors: vectors,
            take: take,
          ));
    final chosen = picked.toSet();
    final rest = [
      for (final id in ids)
        if (!chosen.contains(id)) id,
    ];
    return [...picked, ...spreadOrder(rest)];
  }

  /// Los vectores guardados de cada elemento vivo —fragmentos y tramos de
  /// notas—, sin decodificar; [only], de esos solamente.
  Future<Map<String, List<Uint8List>>> _vectorsByItem({
    List<String>? only,
  }) async {
    final byItem = <String, List<Uint8List>>{};
    Future<void> read(List<String>? ids) async {
      final inIds = ids == null
          ? ''
          : ' AND x.item_id IN (${List.filled(ids.length, '?').join(', ')})';
      final variables = [
        for (final id in ids ?? const <String>[]) Variable.withString(id),
      ];
      final rows = await _db
          .customSelect(
            'SELECT x.item_id AS item_id, x.vector AS vector FROM ( '
            'SELECT c.item_id AS item_id, e.vector AS vector '
            'FROM embeddings e JOIN chunks c ON c.id = e.chunk_id '
            'UNION ALL '
            'SELECT n.item_id, n.vector FROM note_embedding n) x '
            'JOIN item i ON i.id = x.item_id '
            'WHERE ${activeItemSql('i')}$inIds',
            variables: variables,
            readsFrom: {
              _db.embeddings,
              _db.chunks,
              _db.noteEmbeddings,
              _db.knowledgeEntries,
            },
          )
          .get();
      for (final row in rows) {
        (byItem[row.read<String>('item_id')] ??= []).add(
          row.read<Uint8List>('vector'),
        );
      }
    }

    if (only == null) {
      await read(null);
    } else {
      for (var i = 0; i < only.length; i += _idsPerQuery) {
        await read(only.sublist(i, math.min(i + _idsPerQuery, only.length)));
      }
    }
    return byItem;
  }
}

/// [items] en un orden que va de lo grueso a lo fino (F30): primero el del
/// medio, después los del medio de cada mitad, y así —`spreadIndices` con 1,
/// 2, 4… posiciones—. Cortado en cualquier punto, lo elegido queda repartido
/// por toda la lista, y no amontonado al principio.
List<T> spreadOrder<T>(List<T> items) {
  final order = <T>[];
  final seen = <int>{};
  for (var count = 1; seen.length < items.length; count *= 2) {
    for (final index in spreadIndices(items.length, count)) {
      if (seen.add(index)) order.add(items[index]);
    }
  }
  return order;
}

/// El parecido mayor de cada elemento con `query`, si llega al mínimo. Los
/// vectores de otra dimensión —de otro modelo— no se comparan.
Map<String, double> _bestPerItem(
  ({
    List<double> query,
    Map<String, List<Uint8List>> vectors,
    double minSimilarity,
  })
  input,
) {
  final scores = <String, double>{};
  for (final MapEntry(key: itemId, value: blobs) in input.vectors.entries) {
    var best = double.negativeInfinity;
    for (final blob in blobs) {
      final vector = decodeEmbeddingVector(blob);
      if (vector.length != input.query.length) continue;
      best = math.max(best, cosineSimilarity(input.query, vector));
    }
    if (best >= input.minSimilarity) scores[itemId] = best;
  }
  return scores;
}

/// Los primeros `take` de `ids` por cobertura (F30): el más cercano al centro
/// de todos, y después, uno por vez, el más lejano de los ya elegidos —el
/// recorrido del «punto más lejano»—. Cada elemento se describe por el centro
/// de sus vectores. Con la dimensión más común: un vector de otro modelo no se
/// mezcla.
List<String> _farthestPointOrder(
  ({List<String> ids, Map<String, List<Uint8List>> vectors, int take}) input,
) {
  final decoded = <String, List<List<double>>>{
    for (final id in input.ids)
      id: [for (final blob in input.vectors[id]!) decodeEmbeddingVector(blob)],
  };
  final dimensions = <int, int>{};
  for (final vectors in decoded.values) {
    for (final vector in vectors) {
      dimensions[vector.length] = (dimensions[vector.length] ?? 0) + 1;
    }
  }
  final dimension = dimensions.entries
      .reduce((a, b) => b.value > a.value ? b : a)
      .key;

  final ids = <String>[];
  final centers = <List<double>>[];
  for (final id in input.ids) {
    final vectors = [
      for (final vector in decoded[id]!)
        if (vector.length == dimension) vector,
    ];
    if (vectors.isEmpty) continue;
    ids.add(id);
    centers.add(centroid(vectors));
  }
  if (ids.isEmpty) return const [];

  final middle = centroid(centers);
  var first = 0;
  var firstScore = double.negativeInfinity;
  for (var i = 0; i < centers.length; i++) {
    final score = cosineSimilarity(middle, centers[i]);
    if (score > firstScore) {
      firstScore = score;
      first = i;
    }
  }

  final order = [first];
  final distance = [
    for (final center in centers) 1 - cosineSimilarity(centers[first], center),
  ];
  final taken = {first};
  final wanted = math.min(input.take, ids.length);
  while (order.length < wanted) {
    var next = -1;
    for (var i = 0; i < centers.length; i++) {
      if (taken.contains(i)) continue;
      if (next < 0 || distance[i] > distance[next]) next = i;
    }
    order.add(next);
    taken.add(next);
    for (var i = 0; i < centers.length; i++) {
      if (taken.contains(i)) continue;
      distance[i] = math.min(
        distance[i],
        1 - cosineSimilarity(centers[next], centers[i]),
      );
    }
  }
  return [for (final index in order) ids[index]];
}
