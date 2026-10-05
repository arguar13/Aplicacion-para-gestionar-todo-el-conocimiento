import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/chat_conversation.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/domain/entities/persisted_chat_message.dart';
import 'package:sinapsis/core/network/model_download_providers.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/chat/data/repositories/chat_conversation_repository_impl.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model.dart';
import 'package:sinapsis/features/chat/data/services/gemma_chat_model_manager.dart';
import 'package:sinapsis/features/chat/data/services/gemma_engine.dart';
import 'package:sinapsis/features/chat/data/services/http_gemma_model_downloader.dart';
import 'package:sinapsis/features/chat/data/services/language_model_backend_store.dart';
import 'package:sinapsis/features/chat/data/services/language_model_benchmark.dart';
import 'package:sinapsis/features/chat/domain/repositories/chat_conversation_repository.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model_manager.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/chat/domain/services/vault_retriever.dart';
import 'package:sinapsis/features/chat/domain/usecases/ask_vault_question_usecase.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/flashcards/domain/services/quiz_question_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/domain/services/summarization_service.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notes/domain/services/derived_note_generator.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/model_download_notifier.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

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

/// La descarga del modelo de lenguaje, viva aparte de su pantalla (ver
/// [ModelDownloadNotifier]): una sola a la vez, de la opción que estaba
/// elegida al empezarla —la pantalla no deja cambiar de opción mientras
/// tanto—. NO autoDispose: tiene que seguir aunque nadie la mire.
final chatModelDownloadProvider =
    StateNotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
      (ref) => ModelDownloadNotifier(
        keeper: modelDownloadKeeper(ref),
        detail: LongWorkDetail.languageModel,
        // La IA que organiza sola esperaba este modelo (F27): sin el aviso
        // seguiría diciendo que falta hasta que otra cosa la despertara —un
        // elemento nuevo, el cargador—.
        onFinished: () => unawaited(ref.read(aiOrganizeQueueProvider).wake()),
      ),
    );

/// El que de verdad baja el modelo — ver `HttpGemmaModelDownloader` para el
/// motivo por el que esto no se le deja a `flutter_gemma`. NO autoDispose,
/// mismo motivo que [chatModelManagerProvider]: una instancia nueva en
/// medio de una descarga perdería el archivo parcial que ya se estaba
/// retomando.
final gemmaModelDownloaderProvider = Provider<HttpGemmaModelDownloader>((ref) {
  final storage = ref.watch(modelStorageProvider);
  return HttpGemmaModelDownloader(
    transfer: ref.watch(modelFileTransferProvider),
    rootDirectory: storage.root,
    earlierRoots: storage.earlierRoots,
  );
});

/// El modelo de Gemma en sí queda cargado en memoria entre usos —ver
/// `GemmaChatModel`—, así que tampoco es `autoDispose`: perderlo forzaría a
/// recargar varios cientos de megas la próxima vez. Una sola instancia
/// compartida entre el chat y el generador de tarjetas, para que las dos
/// funciones usen el mismo modelo ya cargado en vez de cada una el suyo.
final _gemmaModelProvider = Provider<GemmaChatModel>(
  (ref) => GemmaChatModel(
    gate: ref.watch(languageModelGateProvider),
    engine: ref.watch(gemmaEngineProvider),
    meter: ref.watch(languageModelMeterProvider),
  ),
);

/// El modelo de Gemma cargado en memoria, uno solo en toda la app (ver
/// `GemmaEngine`). NO autoDispose: perderlo es volver a cargar ~3,7 GB.
final gemmaEngineProvider = Provider<GemmaEngine>(
  (ref) => GemmaEngine(
    // Leído al usarlo, no observado: elegir otra opción no tiene por qué
    // descartar el modelo ya cargado de la sesión.
    ensureReady: () => ref.read(chatModelManagerProvider).isReady(),
    meter: ref.watch(languageModelMeterProvider),
    backends: ref.watch(languageModelBackendStoreProvider),
  ),
);

/// En qué parte del teléfono correr el modelo, y lo medido para elegirlo
/// (F30): uno por modelo elegido.
final languageModelBackendStoreProvider = Provider<LanguageModelBackendStore>(
  (ref) => LanguageModelBackendStore(
    preferences: ref.watch(sharedPreferencesProvider),
    modelKey: () => ref.read(chatModelOptionNotifierProvider).name,
  ),
);

/// Medir GPU y CPU en este teléfono y elegir la más rápida (F30).
final languageModelBenchmarkProvider = Provider<LanguageModelBenchmark>(
  (ref) => LanguageModelBenchmark(
    gate: ref.watch(languageModelGateProvider),
    engine: ref.watch(gemmaEngineProvider),
    store: ref.watch(languageModelBackendStoreProvider),
  ),
);

/// Lo medido del modelo de lenguaje en esta sesión (F30): lo muestra la
/// pantalla del modelo.
final languageModelMeterProvider = Provider<LanguageModelMeter>(
  (ref) => LanguageModelMeter(),
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

/// Quien dice qué va en un cuaderno de «Crear con IA» (F30): el modelo de la
/// persona, con su turno.
final notebookCandidateJudgeProvider = Provider<NotebookCandidateJudge>((ref) {
  return ref.watch(_gemmaModelProvider);
});

/// Quien propone nombre y descripción para los cuadernos sugeridos (F30): el
/// modelo de la persona, con su turno.
final notebookNamerProvider = Provider<NotebookNamer>((ref) {
  return ref.watch(_gemmaModelProvider);
});

/// El buscador del chat con la bóveda: los pasajes que hablan de lo
/// preguntado, con una sola consulta (F30, `ChunkPassageRetriever`).
final vaultRetrieverProvider = Provider.autoDispose<VaultRetriever>((ref) {
  return ChunkPassageRetriever(database: ref.watch(appDatabaseProvider));
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
