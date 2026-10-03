import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/features/suggestions/domain/repositories/suggestion_repository.dart';

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

/// Todas las sugerencias de duplicado pendientes de toda la bóveda, para
/// la pantalla "Posibles duplicados" (F7).
final pendingDuplicateSuggestionsProvider =
    StreamProvider.autoDispose<List<Suggestion>>((ref) {
      return ref
          .watch(suggestionRepositoryProvider)
          .watchPendingDuplicateSuggestions();
    });

/// Las sugerencias de propiedad pendientes de toda la bóveda, agrupadas por
/// categoría y valor propuesto, para revisarlas en lote.
///
/// `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto seguiría recomponiéndose aunque ninguna
/// pantalla lo esté mostrando.
final pendingPropertySuggestionGroupsProvider =
    StreamProvider.autoDispose<List<PropertySuggestionGroup>>((ref) {
      return ref
          .watch(suggestionRepositoryProvider)
          .watchPendingPropertySuggestionGroups();
    });
