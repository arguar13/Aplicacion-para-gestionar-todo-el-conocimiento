import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';

import '../../../../support/fake_embedding_service.dart';

/// Contra SQLite real, en memoria, sembrando `KnowledgeEntries`/`Chunks`
/// directo a mano —más simple que pasar por `chunkAndPersistSource` para
/// probar solo el indexador, que no le importa de dónde salieron los
/// chunks.
void main() {
  late AppDatabase db;
  late FakeEmbeddingService embeddings;
  late ChunkEmbeddingIndexerImpl indexer;

  final now = DateTime(2026, 9, 18, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    embeddings = FakeEmbeddingService();
    indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: embeddings,
      clock: () => now,
    );
  });

  tearDown(() => db.close());

  Future<String> seedItem() async {
    final id = 'item-${DateTime.now().microsecondsSinceEpoch}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: 'Un elemento',
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    return id;
  }

  Future<void> seedChunks(String itemId, int count) async {
    for (var i = 0; i < count; i++) {
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: '$itemId-chunk-$i',
              itemId: itemId,
              seq: i,
              content: 'Contenido del fragmento $i',
              charStart: i * 10,
              charEnd: (i + 1) * 10,
            ),
          );
    }
  }

  test('un ítem sin chunks: 0, sin llamar al servicio', () async {
    final itemId = await seedItem();

    final result = await indexer.indexItem(itemId);

    expect(result, 0);
    expect(embeddings.requests, isEmpty);
  });

  test('un ítem con 3 chunks sin embeddings: 3 filas nuevas', () async {
    final itemId = await seedItem();
    await seedChunks(itemId, 3);

    final result = await indexer.indexItem(itemId);

    expect(result, 3);
    final rows = await (db.select(
      db.embeddings,
    )..where((e) => e.chunkId.like('$itemId-chunk-%'))).get();
    expect(rows, hasLength(3));
    expect(decodeEmbeddingVector(rows.first.vector), isNotEmpty);
  });

  test('correrlo dos veces: la segunda no reinserta nada', () async {
    final itemId = await seedItem();
    await seedChunks(itemId, 3);
    await indexer.indexItem(itemId);

    final result = await indexer.indexItem(itemId);

    expect(result, 0);
    final rows = await (db.select(
      db.embeddings,
    )..where((e) => e.chunkId.like('$itemId-chunk-%'))).get();
    expect(rows, hasLength(3));
  });
}
