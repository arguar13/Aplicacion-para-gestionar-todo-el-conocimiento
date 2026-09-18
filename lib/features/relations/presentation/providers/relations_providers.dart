import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_model_manager.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_service.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';

/// Deliberadamente NO autoDispose, mismo motivo que
/// `chatModelManagerProvider`: descartarlo al cerrar la pantalla de
/// descarga perdería el progreso de una descarga en curso. Reusa
/// [gemmaModelDownloaderProvider] de `chat`: `HttpGemmaModelDownloader` es
/// genérico —url/fileName/token por llamado—, sin nada específico del
/// modelo de chat.
final embeddingModelManagerProvider = Provider<EmbeddingModelManager>((ref) {
  return GemmaEmbeddingModelManager(
    downloader: ref.watch(gemmaModelDownloaderProvider),
  );
});

/// El embedder de `flutter_gemma` queda cargado en memoria entre usos —ver
/// `GemmaEmbeddingService`—, así que tampoco es `autoDispose`: perderlo
/// forzaría a resolverlo de nuevo en cada indexación.
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  return GemmaEmbeddingService();
});

final chunkEmbeddingIndexerProvider = Provider<ChunkEmbeddingIndexer>((ref) {
  return ChunkEmbeddingIndexerImpl(
    database: ref.watch(appDatabaseProvider),
    embeddings: ref.watch(embeddingServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

final relationCandidateSelectorProvider = Provider<RelationCandidateSelector>((
  ref,
) {
  return RelationCandidateSelectorImpl(
    database: ref.watch(appDatabaseProvider),
  );
});
