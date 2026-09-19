import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/usecases/generate_property_suggestions_usecase.dart';
import 'package:sinapsis/features/suggestions/data/usecases/generate_relation_suggestions_usecase.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/relation_suggestion_generator.dart';

final suggestionRepositoryProvider = Provider<SuggestionRepository>((ref) {
  return SuggestionRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    organize: ref.watch(organizeRepositoryProvider),
    merge: ref.watch(mergeDuplicateItemsUseCaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Las sugerencias `pending` de un elemento, para el 4º botón de la
/// Bandeja — `autoDispose`, se recalcula sola cuando la pantalla que la
/// mira se cierra.
final pendingSuggestionsProvider = StreamProvider.autoDispose
    .family<List<Suggestion>, String>((ref, itemId) {
      return ref
          .watch(suggestionRepositoryProvider)
          .watchPendingSuggestions(itemId);
    });

final propertySuggestionGeneratorProvider =
    Provider<PropertySuggestionGenerator>((ref) {
      return GeneratePropertySuggestionsUseCase(
        database: ref.watch(appDatabaseProvider),
        service: ref.watch(propertySuggestionServiceProvider),
        modelManager: ref.watch(chatModelManagerProvider),
        organize: ref.watch(organizeRepositoryProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });

final relationSuggestionGeneratorProvider =
    Provider<RelationSuggestionGenerator>((ref) {
      return GenerateRelationSuggestionsUseCase(
        database: ref.watch(appDatabaseProvider),
        ids: ref.watch(idGeneratorProvider),
        embeddingModelManager: ref.watch(embeddingModelManagerProvider),
        indexer: ref.watch(chunkEmbeddingIndexerProvider),
        selector: ref.watch(relationCandidateSelectorProvider),
        chatModelManager: ref.watch(chatModelManagerProvider),
        service: ref.watch(relationSuggestionServiceProvider),
        organize: ref.watch(organizeRepositoryProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      );
    });
