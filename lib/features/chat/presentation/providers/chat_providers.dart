import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/data/services/library_vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

/// Deliberadamente NO autoDispose, mismo motivo que
/// `whisperModelManagerProvider`: descartarlo al cerrar la pantalla de
/// descarga perdería el progreso de una descarga en curso.
final chatModelManagerProvider = Provider<ChatModelManager>((ref) {
  return const GemmaChatModelManager();
});

/// El modelo de Gemma en sí queda cargado en memoria entre usos —ver
/// `GemmaChatModel`—, así que tampoco es `autoDispose`: perderlo forzaría a
/// recargar varios cientos de megas la próxima vez. Una sola instancia
/// compartida entre el chat y el generador de tarjetas, para que las dos
/// funciones usen el mismo modelo ya cargado en vez de cada una el suyo.
final _gemmaModelProvider = Provider<GemmaChatModel>((ref) => GemmaChatModel());

final chatModelProvider = Provider<ChatModel>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final flashcardGeneratorProvider = Provider<FlashcardGenerator>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final relationSuggestionServiceProvider = Provider<RelationSuggestionService>((
  ref,
) {
  return ref.watch(_gemmaModelProvider);
});

final vaultRetrieverProvider = Provider.autoDispose<VaultRetriever>((ref) {
  return LibraryVaultRetriever(library: ref.watch(libraryRepositoryProvider));
});

final askVaultQuestionUseCaseProvider =
    Provider.autoDispose<AskVaultQuestionUseCase>(
      (ref) => AskVaultQuestionUseCase(
        retriever: ref.watch(vaultRetrieverProvider),
        model: ref.watch(chatModelProvider),
        modelManager: ref.watch(chatModelManagerProvider),
      ),
    );
