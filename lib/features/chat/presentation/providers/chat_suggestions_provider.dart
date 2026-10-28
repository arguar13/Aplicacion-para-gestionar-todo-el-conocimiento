import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/features/chat/domain/services/chat_suggestions.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_suggestions_controller.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

/// Cuántos títulos recientes alimentan las sugerencias: uno por sugerencia
/// que los usa (resumir, preguntar, qué dice).
const _kRecentTitles = 3;

/// Dónde se pregunta: el modo y, con la bóveda, el cuaderno (`null` es toda).
typedef ChatSuggestionScope = ({ChatConversationMode mode, String? notebookId});

/// Los títulos de lo último que se guardó **y ya se procesó** —lo pendiente
/// todavía no tiene texto que resumir ni sobre qué preguntar—, en el alcance
/// elegido. `null` mientras se buscan.
///
/// Con un cuaderno, los de sus documentos procesados (F41, paso 5), lo último
/// que se procesó primero: es lo único que un cuaderno tiene, y el chat acotado
/// a él lee solo eso.
final _recentTitlesProvider = Provider.autoDispose
    .family<List<String>?, String?>((ref, notebookId) {
      if (notebookId == null) {
        const recent = LibraryQuery(
          processingStates: {ProcessingState.ready},
          limit: _kRecentTitles,
        );
        final items = ref.watch(libraryItemsProvider(recent)).valueOrNull;
        return items == null ? null : [for (final item in items) item.title];
      }
      final scoped = ref
          .watch(notebookProcessedQueryProvider(notebookId))
          .valueOrNull;
      if (scoped == null) return null;
      final documents = ref
          .watch(
            processedDocumentsProvider(
              scoped.copyWith(
                sortBy: ProcessedSort.createdAt,
                descending: true,
                limit: _kRecentTitles,
                offset: 0,
              ),
            ),
          )
          .valueOrNull;
      return documents == null
          ? null
          : [for (final document in documents) document.title];
    });

/// Las sugerencias del chat vacío (F42), al día con lo que entra: con la
/// bóveda, armadas con lo último guardado, el tema con más cosas o el
/// cuaderno elegido (`vaultChatSuggestions`); en conversación libre, tres
/// comienzos. Vacía mientras se buscan.
final chatSuggestionsProvider = Provider.autoDispose
    .family<List<ChatSuggestion>, ChatSuggestionScope>((ref, scope) {
      if (scope.mode == ChatConversationMode.free) return freeChatSuggestions;

      final recent = ref.watch(_recentTitlesProvider(scope.notebookId));
      if (recent == null) return const [];

      final notebookId = scope.notebookId;
      final notebookName = notebookId == null
          ? null
          : ref.watch(notebookByIdProvider(notebookId)).valueOrNull?.name;
      return vaultChatSuggestions(
        recentTitles: recent,
        notebookName: notebookName,
        topTopic: notebookId == null
            ? topNotebookTopic(ref.watch(notebookTopicsProvider).valueOrNull)
            : null,
      );
    });

/// El tema con más elementos —si no hay temas, la etiqueta con más—.
@visibleForTesting
String? topNotebookTopic(List<NotebookTopic>? topics) {
  if (topics == null || topics.isEmpty) return null;
  NotebookTopic? best;
  for (final topic in topics) {
    if (best == null ||
        _rank(topic) > _rank(best) ||
        (_rank(topic) == _rank(best) && topic.itemCount > best.itemCount)) {
      best = topic;
    }
  }
  return best?.name;
}

/// Un tema pesa más que una etiqueta: es como la persona ordena su bóveda.
int _rank(NotebookTopic topic) => topic.kind == NotebookTopicKind.space ? 1 : 0;
