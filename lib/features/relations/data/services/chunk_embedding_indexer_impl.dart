import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';

/// [ChunkEmbeddingIndexer] contra `AppDatabase` + [EmbeddingService].
class ChunkEmbeddingIndexerImpl implements ChunkEmbeddingIndexer {
  const ChunkEmbeddingIndexerImpl({
    required AppDatabase database,
    required EmbeddingService embeddings,
    required Clock clock,
    this.modelVersion = 'embeddinggemma-300m-8bit',
  }) : _db = database,
       _embeddings = embeddings,
       _clock = clock;

  final AppDatabase _db;
  final EmbeddingService _embeddings;
  final Clock _clock;

  /// Identifica con qué modelo se calculó cada vector — hoy siempre el
  /// mismo (D9 de F5: un solo modelo fijo, sin selector), pero la columna
  /// ya existe desde F1 pensando en esto.
  final String modelVersion;

  @override
  Future<int> indexItem(String itemId) async {
    final chunks = await (_db.select(
      _db.chunks,
    )..where((c) => c.itemId.equals(itemId))).get();
    if (chunks.isEmpty) return 0;

    final existing =
        await (_db.select(_db.embeddings)
              ..where((e) => e.chunkId.isIn(chunks.map((c) => c.id))))
            .map((row) => row.chunkId)
            .get();
    final existingIds = existing.toSet();

    final missing = chunks.where((c) => !existingIds.contains(c.id)).toList();
    if (missing.isEmpty) return 0;

    final vectors = await _embeddings.embedBatch(
      missing.map((c) => c.content).toList(),
    );

    final now = _clock();
    for (var i = 0; i < missing.length; i++) {
      await _db
          .into(_db.embeddings)
          .insert(
            EmbeddingsCompanion.insert(
              chunkId: missing[i].id,
              vector: encodeEmbeddingVector(vectors[i]),
              modelVersion: modelVersion,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    return missing.length;
  }
}
