import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/data/services/library_vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

/// Deliberadamente NO autoDispose, mismo motivo que
/// `whisperModelManagerProvider`: descartarlo al cerrar la pantalla de
/// descarga perdería el progreso de una descarga en curso.
final chatModelManagerProvider = Provider<ChatModelManager>((ref) {
  return const GemmaChatModelManager();
});

/// El modelo de Gemma en sí queda cargado en memoria entre preguntas —ver
/// `GemmaChatModel`—, así que tampoco es `autoDispose`: perderlo al cerrar
/// la pantalla del chat forzaría a recargar varios cientos de megas en la
/// siguiente pregunta.
final chatModelProvider = Provider<ChatModel>((ref) {
  return GemmaChatModel();
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
