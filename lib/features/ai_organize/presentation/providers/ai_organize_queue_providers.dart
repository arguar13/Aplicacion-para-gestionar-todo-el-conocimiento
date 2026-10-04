import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/data/services/battery_charging_probe.dart';
import 'package:sinapsis/features/ai_organize/data/services/prefs_ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/data/services/vocabulary_candidates.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_atlas_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_properties_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_reference_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_relate_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_space_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_language.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_atlas_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';

/// Si el dispositivo está enchufado (F27, decisión C). En una computadora de
/// escritorio, «no se sabe» es que no tiene batería: está enchufada.
final chargingProbeProvider = Provider<ChargingProbe>((ref) {
  final desktop =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  return BatteryChargingProbe(unknownMeansPlugged: desktop);
});

/// Desde cuándo organiza sola la IA en este dispositivo (F27).
final aiOrganizeMemoryProvider = Provider<PrefsAiOrganizeMemory>(
  (ref) => PrefsAiOrganizeMemory(
    prefs: ref.watch(sharedPreferencesProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Lo que la IA tiene pendiente, deducido de la base (F27).
final aiOrganizeBacklogProvider = Provider<AiOrganizeBacklog>(
  (ref) => AiOrganizeBacklogImpl(ref.watch(appDatabaseProvider)),
);

/// Lo que hace la IA con cada elemento, en orden (F27): primero lo barato
/// —la referencia, que no usa el modelo—, después lo que más tarda —las
/// tarjetas, varias llamadas al modelo en un texto largo— y al final el
/// Atlas, que necesita los temas ya puestos. Todo con el modelo
/// en el turno de la cola (`backgroundLanguageModelProvider`): le cede el
/// paso a la persona.
final aiOrganizeStepsProvider = Provider<List<AiOrganizeStep>>((ref) {
  final model = ref.watch(backgroundLanguageModelProvider);
  final runs = ref.watch(aiRunRepositoryProvider);
  final organize = ref.watch(organizeRepositoryProvider);
  final suggestions = ref.watch(suggestionRepositoryProvider);
  return [
    AutoReferenceStep(
      files: ref.watch(fileStoreProvider),
      suggestions: suggestions,
      runs: runs,
    ),
    AutoPropertiesStep(
      vocabulary: VocabularyCandidatesReader(
        database: ref.watch(appDatabaseProvider),
        embeddings: ref.watch(embeddingServiceProvider),
        clock: ref.watch(clockProvider),
      ),
      service: model,
      organize: organize,
      suggestions: suggestions,
      runs: runs,
    ),
    AutoSpaceStep(chooser: model.chooseSpace, organize: organize, runs: runs),
    AutoRelateStep(
      database: ref.watch(appDatabaseProvider),
      ids: ref.watch(idGeneratorProvider),
      indexer: ref.watch(chunkEmbeddingIndexerProvider),
      selector: ref.watch(relationCandidateSelectorProvider),
      service: model,
      organize: organize,
      suggestions: suggestions,
      runs: runs,
    ),
    AutoFlashcardsStep(
      generator: model,
      flashcards: ref.watch(flashcardRepositoryProvider),
      suggestions: suggestions,
      runs: runs,
    ),
    // El Atlas, al final: trabaja con los temas que dejaron los de arriba.
    AutoAtlasStep(
      atlas: ref.watch(aiAtlasRepositoryProvider),
      library: ref.watch(libraryRepositoryProvider),
      suggestions: suggestions,
      chooseParent: model.chooseTopicParent,
      writeIntro: model.writeMapIntroduction,
      epoch: ref.watch(aiOrganizeMemoryProvider).epoch,
      modelName: () => ref.read(chatModelOptionNotifierProvider).name,
      // Se lee al escribir, no al armar los pasos: la cola vive toda la
      // sesión, y la persona puede cambiar el idioma en el medio.
      language: () =>
          MapNoteLanguage.of(ref.read(effectiveLocaleProvider).languageCode),
      clock: ref.watch(clockProvider),
    ),
  ];
});

/// Cómo va el pedido de «Crear tarjetas con IA» de Repasar (F30), o `null`
/// si no hay ninguno a la vista. Lo publica la cola.
final aiFlashcardsBatchProvider = StateProvider<AiFlashcardsBatch?>(
  (ref) => null,
);

/// La cola de la IA que organiza sola (F27). Deliberadamente sin
/// `autoDispose` y sin `ref.watch`, mismo criterio que
/// `processingQueueProvider`: vive toda la sesión, y reconstruirla por un
/// cambio en la cadena de proveedores perdería lo que se pidió a mano. Sus
/// dependencias se piden al usarlas.
///
/// Arranca cuando se retoma el trabajo pendiente al abrir la biblioteca
/// (`ProcessingQueueNotifier.resume`). Publica su estado en
/// `aiOrganizeStatusProvider` y sigue los interruptores de
/// `aiOrganizeSettingsProvider`: pausar y reanudar es prender y apagar
/// `AiOrganizeToggle.enabled`.
final aiOrganizeQueueProvider = Provider<AiOrganizeQueue>((ref) {
  final queue = AiOrganizeQueue(
    backlog: ref.read(aiOrganizeBacklogProvider),
    runs: ref.read(aiRunRepositoryProvider),
    library: ref.read(libraryRepositoryProvider),
    steps: () => ref.read(aiOrganizeStepsProvider),
    chatModel: () => ref.read(chatModelManagerProvider),
    embeddingModel: () => ref.read(embeddingModelManagerProvider),
    vectors: () => ref.read(chunkEmbeddingIndexerProvider),
    charging: ref.read(chargingProbeProvider),
    epoch: ref.read(aiOrganizeMemoryProvider).epoch,
    telemetry: ref.read(telemetryServiceProvider),
    clock: ref.read(clockProvider),
    onStatus: (status) =>
        ref.read(aiOrganizeStatusProvider.notifier).state = status,
    settings: ref.read(aiOrganizeSettingsProvider),
    modelName: () => ref.read(chatModelOptionNotifierProvider).name,
    longWork: ref
        .read(longWorkCoordinatorProvider)
        .keeperFor(LongWorkOwner.aiOrganize),
    onFlashcardsBatch: (batch) =>
        ref.read(aiFlashcardsBatchProvider.notifier).state = batch,
  );
  ref
    ..listen(
      aiOrganizeSettingsProvider,
      (_, settings) => queue.updateSettings(settings),
    )
    ..onDispose(queue.dispose);
  return queue;
});
