import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/usecases/backfill_embeddings_usecase.dart';

/// [BackfillEmbeddingsUseCase] contra `AppDatabase` + [ChunkEmbeddingIndexer].
class BackfillEmbeddingsUseCaseImpl implements BackfillEmbeddingsUseCase {
  const BackfillEmbeddingsUseCaseImpl({
    required AppDatabase database,
    required ChunkEmbeddingIndexer indexer,
    required TelemetryService telemetry,
  }) : _db = database,
       _indexer = indexer,
       _telemetry = telemetry;

  final AppDatabase _db;
  final ChunkEmbeddingIndexer _indexer;
  final TelemetryService _telemetry;

  @override
  Stream<EmbeddingBackfillProgress> call() async* {
    final rows =
        await (_db.selectOnly(_db.chunks, distinct: true)
              ..addColumns([_db.chunks.itemId]))
            .map((row) => row.read(_db.chunks.itemId)!)
            .get();

    var indexedChunks = 0;
    for (var i = 0; i < rows.length; i++) {
      try {
        indexedChunks += await _indexer.indexItem(rows[i]);
        // Sin `on Object catch`: un ítem que falla se reporta y se sigue
        // con el resto, mismo criterio que `chunkAndPersistSource` con
        // `MigrationIssues` — un embedding que no se pudo calcular no
        // puede cortar el backfill de todos los demás.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'BackfillEmbeddingsUseCase: itemId=${rows[i]}',
        );
      }

      yield EmbeddingBackfillProgress(
        processedItems: i + 1,
        totalItems: rows.length,
        indexedChunks: indexedChunks,
      );
    }
  }
}
