import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/network/network_providers.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/data/repositories/chat_conversation_repository_impl.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/chat/data/services/library_vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/repositories/chat_conversation_repository.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/domain/services/summarization_service.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Deliberadamente NO autoDispose, mismo motivo que
/// `whisperModelManagerProvider`: descartarlo al cerrar la pantalla de
/// descarga perdería el progreso de una descarga en curso.
///
/// Depende de [chatModelOptionNotifierProvider] para saber a qué opción
/// apuntar: cambiar la opción elegida en la pantalla de descarga arma una
/// instancia nueva apuntando al repositorio que corresponde, en vez de que
/// el manager cargue con un modelo fijo de una vez para siempre.
final chatModelManagerProvider = Provider<ChatModelManager>((ref) {
  final option = ref.watch(chatModelOptionNotifierProvider);
  return GemmaChatModelManager(
    option: option,
    downloader: ref.watch(gemmaModelDownloaderProvider),
  );
});

/// El que de verdad baja el modelo — ver `HttpGemmaModelDownloader` para el
/// motivo por el que esto no se le deja a `flutter_gemma`. NO autoDispose,
/// mismo motivo que [chatModelManagerProvider]: una instancia nueva en
/// medio de una descarga perdería el archivo parcial que ya se estaba
/// retomando.
final gemmaModelDownloaderProvider = Provider<HttpGemmaModelDownloader>((ref) {
  return HttpGemmaModelDownloader(
    dio: ref.watch(gemmaModelDioProvider),
    rootDirectory: getApplicationDocumentsDirectory,
  );
});

/// El modelo de Gemma en sí queda cargado en memoria entre usos —ver
/// `GemmaChatModel`—, así que tampoco es `autoDispose`: perderlo forzaría a
/// recargar varios cientos de megas la próxima vez. Una sola instancia
/// compartida entre el chat y el generador de tarjetas, para que las dos
/// funciones usen el mismo modelo ya cargado en vez de cada una el suyo.
final _gemmaModelProvider = Provider<GemmaChatModel>(
  (ref) => GemmaChatModel(gate: ref.watch(languageModelGateProvider)),
);

/// El turno para usar el modelo de lenguaje (F27): uno a la vez, la persona
/// antes que la cola de la IA. Uno solo en toda la app, como el modelo.
final languageModelGateProvider = Provider<LanguageModelGate>(
  (ref) => LanguageModelGate(
    onError: (error, stackTrace) => ref
        .read(telemetryServiceProvider)
        .recordError(
          error,
          stackTrace,
          hint: 'LanguageModelGate: cerrar una charla sin uso',
        ),
  ),
);

/// El mismo modelo ya cargado, con el turno de la cola de la IA (F27): espera
/// a que la persona no lo esté usando. Solo para los pasos de la IA que
/// organiza sola; la interfaz usa los de arriba.
final backgroundLanguageModelProvider = Provider<GemmaChatModel>(
  (ref) => ref.watch(_gemmaModelProvider).background,
);

final chatModelProvider = Provider<ChatModel>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final flashcardGeneratorProvider = Provider<FlashcardGenerator>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final quizQuestionGeneratorProvider = Provider<QuizQuestionGenerator>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final relationSuggestionServiceProvider = Provider<RelationSuggestionService>((
  ref,
) {
  return ref.watch(_gemmaModelProvider);
});

final summarizationServiceProvider = Provider<SummarizationService>((ref) {
  return ref.watch(_gemmaModelProvider);
});

final propertySuggestionServiceProvider = Provider<PropertySuggestionService>((
  ref,
) {
  return ref.watch(_gemmaModelProvider);
});

final derivedNoteGeneratorProvider = Provider<DerivedNoteGenerator>((ref) {
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

final chatConversationRepositoryProvider = Provider<ChatConversationRepository>(
  (ref) {
    return ChatConversationRepositoryImpl(
      database: ref.watch(appDatabaseProvider),
      telemetry: ref.watch(telemetryServiceProvider),
      ids: ref.watch(idGeneratorProvider),
      clock: ref.watch(clockProvider),
    );
  },
);

/// Las conversaciones guardadas de un modo, más nueva primero — para el
/// menú de historial.
final chatConversationsProvider = StreamProvider.autoDispose
    .family<List<ChatConversation>, ChatConversationMode>((ref, mode) {
      return ref
          .watch(chatConversationRepositoryProvider)
          .watchConversations(mode);
    });

/// Los mensajes guardados de una conversación abierta.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<PersistedChatMessage>, String>((ref, conversationId) {
      return ref
          .watch(chatConversationRepositoryProvider)
          .watchMessages(conversationId);
    });

/// Los bytes de un adjunto ya guardado, para dibujar su miniatura en un
/// mensaje del historial. `autoDispose` y cacheado por ruta: varios mensajes
/// que compartieran el mismo adjunto —no pasa hoy, pero tampoco cuesta
/// nada— no repetirían la lectura de disco.
final chatAttachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, relativePath) {
      return ref.watch(fileStoreProvider).read(relativePath);
    });
