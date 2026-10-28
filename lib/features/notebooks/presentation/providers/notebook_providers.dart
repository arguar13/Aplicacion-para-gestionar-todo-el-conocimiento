import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/notebooks/data/repositories/notebook_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/services/notebook_candidate_finder_impl.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';

/// Cascada de inyección de los cuadernos (F16).
final notebookRepositoryProvider = Provider<NotebookRepository>((ref) {
  return NotebookRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    processed: ref.watch(processedRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Los cuadernos, actualizándose solos.
final notebooksProvider = StreamProvider.autoDispose<List<Notebook>>((ref) {
  return ref.watch(notebookRepositoryProvider).watchAll();
});

/// Uno solo, para la pantalla de detalle.
final notebookByIdProvider = StreamProvider.autoDispose
    .family<Notebook?, String>((ref, id) {
      return ref.watch(notebookRepositoryProvider).watchById(id);
    });

/// Los ids de un cuaderno manual —ver `NotebookRepository.watchItemIds`—.
final notebookItemIdsProvider = StreamProvider.autoDispose
    .family<Set<String>, String>((ref, notebookId) {
      return ref.watch(notebookRepositoryProvider).watchItemIds(notebookId);
    });

/// Qué documentos procesados pide un cuaderno (F41, paso 5) —ver
/// `NotebookRepository.resolveQuery`—, otra vez cada vez que cambia: el
/// cuaderno —su modo o su consulta— o lo que se le agregó o sacó.
final notebookProcessedQueryProvider = FutureProvider.autoDispose
    .family<ProcessedQuery, String>((ref, notebookId) async {
      ref
        ..watch(notebookByIdProvider(notebookId))
        ..watch(notebookItemIdsProvider(notebookId));
      return ref.watch(notebookRepositoryProvider).resolveQuery(notebookId);
    });

/// Qué modelos hay para los cuadernos con IA (F30): el de lenguaje —el
/// elegido, bajado o en la nube (F32)— revisa y nombra; el de vínculos busca
/// por sentido.
final notebookAiModelsProvider =
    FutureProvider.autoDispose<({bool language, bool sense})>(
      (ref) async => (
        language: (await ref.watch(languageModelStatusProvider.future)).isReady,
        sense: await ref.watch(embeddingModelManagerProvider).isReady(),
      ),
    );

/// Dónde busca «Crear con IA» lo que podría ir en un cuaderno (F30): por
/// palabras y, con el modelo de vínculos, también por sentido.
final notebookCandidateFinderProvider =
    Provider.autoDispose<NotebookCandidateFinder>(
      (ref) => NotebookCandidateFinderImpl(
        database: ref.watch(appDatabaseProvider),
        processed: ref.watch(processedRepositoryProvider),
        retriever: ref.watch(vaultRetrieverProvider),
        vectors: ref.watch(itemVectorIndexProvider),
        embeddings: ref.watch(embeddingServiceProvider),
        embeddingsReady: () =>
            ref.read(embeddingModelManagerProvider).isReady(),
        telemetry: ref.watch(telemetryServiceProvider),
      ),
    );
