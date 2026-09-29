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

  /// Cuántos fragmentos se piden y se guardan por vez: ver [indexItem].
  static const batchSize = 32;

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

    // Por tandas, guardando cada una (F21): un libro de 500 páginas son unos
    // mil fragmentos, y pedirlos todos juntos era todo o nada —si la app se
    // cerraba a mitad de camino no quedaba ningún vector, y la vez siguiente
    // se empezaba de cero—. Así lo guardado queda, y la próxima pasada sigue
    // desde lo que falta.
    for (var start = 0; start < missing.length; start += batchSize) {
      final batch = missing.sublist(
        start,
        (start + batchSize).clamp(0, missing.length),
      );
      final vectors = await _embeddings.embedBatch(
        batch.map((c) => c.content).toList(),
      );

      final now = _clock();
      await _db.batch((b) {
        for (var i = 0; i < batch.length; i++) {
          b.insert(
            _db.embeddings,
            EmbeddingsCompanion.insert(
              chunkId: batch[i].id,
              vector: encodeEmbeddingVector(vectors[i]),
              modelVersion: modelVersion,
              createdAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    }
    return missing.length;
  }
}
