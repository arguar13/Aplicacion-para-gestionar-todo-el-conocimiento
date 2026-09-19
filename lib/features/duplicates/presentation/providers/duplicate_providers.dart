import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/duplicates/data/repositories/duplicate_provenance_repository_impl.dart';
import 'package:sinapsis/features/duplicates/data/services/duplicate_candidate_selector_impl.dart';
import 'package:sinapsis/features/duplicates/data/usecases/generate_duplicate_suggestions_usecase.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/duplicates/domain/entities/merged_provenance.dart';
import 'package:sinapsis/features/duplicates/domain/repositories/duplicate_provenance_repository.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_candidate_selector.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/duplicates/domain/usecases/merge_duplicate_items_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final duplicateProvenanceRepositoryProvider =
    Provider<DuplicateProvenanceRepository>((ref) {
      return DuplicateProvenanceRepositoryImpl(
        database: ref.watch(appDatabaseProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });

/// Qué otras procedencias absorbió un elemento al fusionarse con
/// duplicados — vacío para la inmensa mayoría, que nunca se fusionó con
/// nada.
final mergedProvenancesForItemProvider = StreamProvider.autoDispose
    .family<List<MergedProvenance>, String>((ref, itemId) {
      return ref
          .watch(duplicateProvenanceRepositoryProvider)
          .watchMergedProvenancesForItem(itemId);
    });

final duplicateCandidateSelectorProvider = Provider<DuplicateCandidateSelector>(
  (ref) {
    return DuplicateCandidateSelectorImpl(
      database: ref.watch(appDatabaseProvider),
    );
  },
);

final mergeDuplicateItemsUseCaseProvider = Provider<MergeDuplicateItemsUseCase>(
  (ref) {
    return MergeDuplicateItemsUseCaseImpl(
      database: ref.watch(appDatabaseProvider),
      library: ref.watch(libraryRepositoryProvider),
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
      telemetry: ref.watch(telemetryServiceProvider),
    );
  },
);

final duplicateSuggestionGeneratorProvider =
    Provider<DuplicateSuggestionGenerator>((ref) {
      return GenerateDuplicateSuggestionsUseCase(
        database: ref.watch(appDatabaseProvider),
        selector: ref.watch(duplicateCandidateSelectorProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });
