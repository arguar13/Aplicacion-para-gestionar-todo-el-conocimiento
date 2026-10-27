import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/i18n/locale_notifier.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_task_providers.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/data/services/battery_charging_probe.dart';
import 'package:sinapsis/features/ai_organize/data/services/prefs_ai_organize_memory.dart';
import 'package:sinapsis/features/ai_organize/data/services/vocabulary_candidates.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_atlas_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_dates_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_properties_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_reference_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_relate_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_space_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/review_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/review_things_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_dates_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_flashcards_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_batch.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_organize_backlog.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_item_reviewer.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_review_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/ai_organize/domain/services/map_note_language.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_atlas_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/relations/presentation/providers/relations_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/timeline/presentation/providers/dated_event_providers.dart';
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
/// —la referencia, que no usa el modelo—, después las fechas de la línea de
/// tiempo, que no llaman al modelo si el texto no trae ninguna, lo que más
/// tarda —las tarjetas, varias llamadas al modelo en un texto largo— y al final
/// el Atlas, que necesita los temas ya puestos. Todo con el modelo
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
    AutoDatesStep(
      extractor: model,
      events: ref.watch(datedEventRepositoryProvider),
    ),
    AutoFlashcardsStep(
      generator: model,
      flashcards: ref.watch(flashcardRepositoryProvider),
      suggestions: suggestions,
      runs: runs,
      textBudget: ref.watch(languageModelTextBudgetProvider),
    ),
    // El Atlas, al final: trabaja con los temas que dejaron los de arriba.
    AutoAtlasStep(
      atlas: ref.watch(aiAtlasRepositoryProvider),
      library: ref.watch(libraryRepositoryProvider),
      suggestions: suggestions,
      chooseParent: model.chooseTopicParent,
      writeIntro: model.writeMapIntroduction,
      epoch: ref.watch(aiOrganizeMemoryProvider).epoch,
      modelName: ref.watch(languageModelNameProvider),
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

/// Cómo va el pedido de «Organizar con IA» de la línea de tiempo (F40), o
/// `null` si no hay ninguno a la vista. Lo publica la cola.
final aiDatesBatchProvider = StateProvider<AiDatesBatch?>((ref) => null);

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
    languageModel: () => ref.read(languageModelStatusCheckProvider),
    embeddingModel: () => ref.read(embeddingModelManagerProvider),
    vectors: () => ref.read(chunkEmbeddingIndexerProvider),
    charging: ref.read(chargingProbeProvider),
    epoch: ref.read(aiOrganizeMemoryProvider).epoch,
    telemetry: ref.read(telemetryServiceProvider),
    clock: ref.read(clockProvider),
    onStatus: (status) =>
        ref.read(aiOrganizeStatusProvider.notifier).state = status,
    settings: ref.read(aiOrganizeSettingsProvider),
    modelName: ref.read(languageModelNameProvider),
    longWork: ref
        .read(longWorkCoordinatorProvider)
        .keeperFor(LongWorkOwner.aiOrganize),
    onFlashcardsBatch: (batch) =>
        ref.read(aiFlashcardsBatchProvider.notifier).state = batch,
    onDatesBatch: (batch) =>
        ref.read(aiDatesBatchProvider.notifier).state = batch,
    tasks: ref.read(aiTaskTrackerProvider),
  );
  ref
    ..listen(
      aiOrganizeSettingsProvider,
      (_, settings) => queue.updateSettings(settings),
    )
    // Elegir otro proveedor, cuenta o modelo, o cargar una clave, puede
    // destrabar lo que la cola esperaba del modelo en la nube (F32).
    ..listen(aiModelSettingsProvider, (_, _) => queue.languageModelChanged())
    ..listen(aiAccountsProvider, (_, _) => queue.languageModelChanged())
    ..onDispose(queue.dispose);
  return queue;
});

/// Quien revisa cada elemento en «Revisar con otro modelo» (F33): las
/// tarjetas, y después lo demás. Con el modelo que pidió la persona pero con
/// el turno de la cola (`requestedBackgroundLanguageModelProvider`): sale de
/// su cuota, no del tope de la IA de fondo, y le cede el modelo cuando lo usa.
final aiItemReviewerProvider = Provider<AiItemReviewer>((ref) {
  final model = ref.watch(requestedBackgroundLanguageModelProvider);
  final textBudget = ref.watch(languageModelTextBudgetProvider);
  return AiItemReviewers(
    [
      ReviewFlashcardsStep(
        reviewer: model,
        flashcards: ref.watch(flashcardRepositoryProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        runs: ref.watch(aiRunRepositoryProvider),
        textBudget: textBudget,
      ),
      ReviewThingsStep(
        reviewer: model,
        runs: ref.watch(aiRunRepositoryProvider),
        atlas: ref.watch(aiAtlasRepositoryProvider),
        suggestions: ref.watch(suggestionRepositoryProvider),
        textBudget: textBudget,
      ),
    ],
    // Los dos pasos de «Cómo lo hace», en el mismo orden (F39).
    steps: const [AiTaskStepKind.reviewFlashcards, AiTaskStepKind.reviewThings],
  );
});

/// Cómo va el pedido de «Revisar con otro modelo» (F33), o `null` si no hay
/// ninguno a la vista. Lo publica la cola de revisión.
final aiReviewBatchProvider = StateProvider<AiReviewBatch?>((ref) => null);

/// La cola de «Revisar con otro modelo» (F33). Como [aiOrganizeQueueProvider],
/// vive toda la sesión y pide sus dependencias al usarlas: reconstruirla
/// perdería lo que la persona pidió revisar.
final aiReviewQueueProvider = Provider<AiReviewQueue>((ref) {
  final queue = AiReviewQueue(
    runs: ref.read(aiRunRepositoryProvider),
    library: ref.read(libraryRepositoryProvider),
    reviewer: () => ref.read(aiItemReviewerProvider),
    languageModel: () => ref.read(languageModelStatusCheckProvider),
    modelName: ref.read(languageModelNameProvider),
    telemetry: ref.read(telemetryServiceProvider),
    clock: ref.read(clockProvider),
    onBatch: (batch) => ref.read(aiReviewBatchProvider.notifier).state = batch,
    longWork: ref
        .read(longWorkCoordinatorProvider)
        .keeperFor(LongWorkOwner.aiReview),
    tasks: ref.read(aiTaskTrackerProvider),
  );
  ref
    // Elegir otro modelo o cargar una clave puede destrabar lo que esperaba.
    ..listen(aiModelSettingsProvider, (_, _) => queue.languageModelChanged())
    ..listen(aiAccountsProvider, (_, _) => queue.languageModelChanged())
    ..onDispose(queue.dispose);
  return queue;
});

/// El modelo que revisaría ahora en «Revisar con otro modelo» (F33), como lo
/// guardan las pasadas: al día con el proveedor, el modelo y la opción de
/// Gemma elegidos, para que el botón diga siempre con cuál.
final aiReviewerNameProvider = Provider.autoDispose<String>(
  (ref) => ref.watch(chosenLanguageModelNameProvider),
);

/// Lo que el modelo elegido todavía tiene para revisar (F33), por el modelo
/// que lo hizo: lo que ofrece la tarjeta de «Lo que hizo la IA». Se vuelve a
/// contar al cambiar de modelo y a medida que avanza una revisión. Si no se
/// puede leer, no se ofrece nada: no hay nada que la persona pueda hacer.
final aiReviewOfferProvider = FutureProvider.autoDispose<List<AiModelWork>>((
  ref,
) async {
  final reviewer = ref.watch(aiReviewerNameProvider);
  ref.watch(aiReviewBatchProvider.select((b) => (b == null, b?.done)));
  return (await ref
          .watch(aiRunRepositoryProvider)
          .aiWorkByModel(reviewer: reviewer))
      .getOrElse((_) => const []);
});

/// A qué modelos ya se les ofreció revisar lo de uno anterior al elegirlos
/// (F33, decisión D): el aviso sale una vez por modelo, se acepte o no.
class AiReviewSwitchOffers {
  const AiReviewSwitchOffers(this._prefs);

  static const _key = 'ai_review_switch_offered';

  final SharedPreferences _prefs;

  bool wasOffered(String model) =>
      (_prefs.getStringList(_key) ?? const []).contains(model);

  Future<void> markOffered(String model) =>
      _prefs.setStringList(_key, [...?_prefs.getStringList(_key), model]);
}

final aiReviewSwitchOffersProvider = Provider<AiReviewSwitchOffers>(
  (ref) => AiReviewSwitchOffers(ref.watch(sharedPreferencesProvider)),
);
