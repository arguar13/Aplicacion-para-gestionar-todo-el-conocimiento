import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/data/repositories/map_similar_source_impl.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/map_similar_source.dart';
import 'package:sinapsis/features/relations/domain/services/item_vector_index.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

import '../../../../support/item_rows.dart';

/// Lo que el índice de vectores recibe: un doble que anota cada pedido y
/// devuelve lo que se le diga.
class _FakeVectors implements ItemVectorIndex {
  final calls =
      <
        ({
          List<String> ids,
          double min,
          int perItem,
          int limit,
          Set<String> except,
        })
      >[];
  List<SimilarPair> answer = const [];

  @override
  Future<List<SimilarPair>> similarPairs(
    List<String> itemIds, {
    required double minSimilarity,
    required int perItem,
    required int limit,
    Set<String> except = const {},
  }) async {
    calls.add((
      ids: itemIds,
      min: minSimilarity,
      perItem: perItem,
      limit: limit,
      except: except,
    ));
    return answer;
  }

  @override
  Future<List<ItemSimilarity>> nearestTo(
    List<double> query, {
    required int limit,
    required double minSimilarity,
    Iterable<String>? among,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> representativeOrder(
    List<String> itemIds, {
    required int take,
  }) => throw UnimplementedError();
}

/// De dónde salen los parecidos del Mapa (F44, paso 5), contra SQLite real en
/// memoria: lo vinculado —en cualquier sentido— queda afuera antes de
/// comparar, y se compara con los topes del Mapa.
void main() {
  late AppDatabase db;
  late _FakeVectors vectors;
  late MapSimilarSource source;
  final now = DateTime(2026, 10, 30, 10);
  var counter = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vectors = _FakeVectors();
    source = mapSimilarSource(database: db, vectors: vectors);
    for (final id in ['a', 'b', 'c', 'd', 'afuera']) {
      await insertItemRows(db, id: id, title: 'Documento $id');
    }
  });

  tearDown(() => db.close());

  Future<void> relate(String from, String to) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'r${counter++}',
          fromItemId: from,
          toItemId: to,
          kind: RelationKind.cites,
          createdAt: now,
        ),
      );

  test('deja afuera los pares ya vinculados, en cualquier sentido, y solo '
      'entre los pedidos', () async {
    await relate('a', 'b');
    await relate('d', 'c');
    await relate('a', 'afuera');
    vectors.answer = [SimilarPair('a', 'c', 0.8)];

    final pairs = await source(['a', 'b', 'c', 'd']);

    expect(pairs, [SimilarPair('a', 'c', 0.8)]);
    final call = vectors.calls.single;
    expect(call.except, {similarPairKey('a', 'b'), similarPairKey('c', 'd')});
    expect(call.ids, ['a', 'b', 'c', 'd']);
    expect(
      (call.min, call.perItem, call.limit),
      (kMapSimilarMinScore, kMapSimilarPerDocument, kMapSimilarPairs),
    );
  });

  test('con menos de dos documentos no compara nada', () async {
    expect(await source(['a']), isEmpty);
    expect(await source(['a', 'a']), isEmpty);
    expect(vectors.calls, isEmpty);
  });

  test('compara a lo sumo los documentos que dibuja el Mapa', () async {
    await source([for (var i = 0; i < kMaxGraphItems + 50; i++) 'x$i']);

    expect(vectors.calls.single.ids, hasLength(kMaxGraphItems));
  });
}
