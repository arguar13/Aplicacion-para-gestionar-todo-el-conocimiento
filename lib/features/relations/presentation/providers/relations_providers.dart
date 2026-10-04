import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_model_manager.dart';
import 'package:sinapsis/features/relations/data/services/gemma_embedding_service.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';
import 'package:sinapsis/features/relations/data/usecases/backfill_embeddings_usecase_impl.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_model_manager.dart';
import 'package:sinapsis/features/relations/domain/services/embedding_service.dart';
import 'package:sinapsis/features/relations/domain/services/relation_candidate_selector.dart';
import 'package:sinapsis/features/relations/domain/usecases/backfill_embeddings_usecase.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

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

/// La descarga del modelo de relaciones, viva aparte de su pantalla (ver
/// [ModelDownloadNotifier]). NO autoDispose: tiene que seguir aunque nadie
/// la mire.
final embeddingModelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
      (ref) => ModelDownloadNotifier(
        keeper: modelDownloadKeeper(ref),
        detail: LongWorkDetail.relationsModel,
        // La IA que organiza sola esperaba este modelo (F27).
        onFinished: () => unawaited(ref.read(aiOrganizeQueueProvider).wake()),
      ),
    );

/// El embedder de `flutter_gemma` queda cargado en memoria entre usos —ver
/// `GemmaEmbeddingService`—, así que tampoco es `autoDispose`: perderlo
/// forzaría a resolverlo de nuevo en cada indexación.
final embeddingServiceProvider = Provider<EmbeddingService>((ref) {
  return GemmaEmbeddingService(
    ensureReady: () => ref.read(embeddingModelManagerProvider).isReady(),
    // La persona primero (F30): con el chat a la vista o el modelo de
    // lenguaje en uso, los vínculos esperan.
    waitForUser: ref.watch(languageModelGateProvider).whenUserIdle,
  );
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

final backfillEmbeddingsUseCaseProvider =
    Provider.autoDispose<BackfillEmbeddingsUseCase>((ref) {
      return BackfillEmbeddingsUseCaseImpl(
        database: ref.watch(appDatabaseProvider),
        indexer: ref.watch(chunkEmbeddingIndexerProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });
