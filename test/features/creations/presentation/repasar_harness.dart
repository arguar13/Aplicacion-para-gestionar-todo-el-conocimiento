import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/entities/account_usage.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../support/library_harness.dart';
import '../../../support/processed_rows.dart';

/// Una llamada que recibió la cola de mentira.
typedef QueueCall = ({String action, String id, Object? detail});

/// La cola de crear de las pruebas de Repasar: no le pide nada a ninguna IA.
/// Guarda los pedidos en el repositorio de verdad —así las filas aparecen en
/// «Lo creado» como en la app— y anota cada llamada.
class FakeCreationQueue extends CreationQueue {
  FakeCreationQueue(this.store)
    : super(
        repository: () => store,
        scopes: () => throw UnimplementedError('sin recortes en la cola falsa'),
        material: () => throw UnimplementedError('sin material'),
        generators: () => const {},
        personWriter: () => throw UnimplementedError('sin IA'),
        backgroundWriter: () => throw UnimplementedError('sin IA'),
      );

  final StudyCreationRepository store;
  final calls = <QueueCall>[];
  final requests = <CreationRequest>[];

  @override
  Future<Either<Failure, StudyCreation>> create(CreationRequest request) {
    requests.add(request);
    calls.add((action: 'create', id: request.kind.storageKey, detail: request));
    return store.create(request);
  }

  @override
  Future<Either<Failure, StudyCreation>> retry(String id, {bool? runNow}) {
    calls.add((action: 'retry', id: id, detail: runNow));
    return store.requeue(id, runNow: runNow);
  }

  @override
  Future<Either<Failure, StudyCreation>> regenerate(
    String id, {
    bool? runNow,
    Map<String, Object?>? options,
    List<String>? sourceIds,
    String? languageCode,
  }) {
    calls.add((
      action: 'regenerate',
      id: id,
      detail: (
        runNow: runNow,
        options: options,
        sourceIds: sourceIds,
        languageCode: languageCode,
      ),
    ));
    return store.requeue(
      id,
      runNow: runNow,
      options: options,
      sourceIds: sourceIds,
      languageCode: languageCode,
    );
  }

  @override
  Future<void> cancel(String id) async {
    calls.add((action: 'cancel', id: id, detail: null));
    await store.fail(id, CreationFailure.cancelled);
  }

  @override
  Future<Either<Failure, Unit>> trash(String id) {
    calls.add((action: 'trash', id: id, detail: null));
    return store.trash(id);
  }

  @override
  Future<void> resume() async {}
}

/// Gemini escribiendo, con su cuota estimada; con [canWrite] apagado, sin
/// cuenta; con [imageAccounts], quién dibujaría.
CreationEstimate fakeEstimate(
  CreationEstimateRequest request, {
  bool canWrite = true,
  List<ImageSide> imageAccounts = const [],
}) => const CreationCostEstimator().estimate(
  text: TextSide(
    provider: AiProvider.gemini,
    model: 'gemini-3.8-flash',
    modelLabel: 'Gemini 3.8 Flash',
    accountId: 'g',
    accountLabel: 'Personal',
    usage: const AccountUsage(accountId: 'g', day: 'd', requests: 50),
    quota: defaultDailyQuota(AiProvider.gemini),
    status: canWrite
        ? const LanguageModelReady(provider: AiProvider.gemini)
        : const LanguageModelNeedsAccount(provider: AiProvider.gemini),
  ),
  inputTokens: request.inputTokens,
  expectedOutputTokens: request.expectedOutputTokens,
  textRequests: request.textRequests,
  images: request.images,
  imageSize: request.imageSize,
  imageAccountId: request.imageAccountId,
  imageAccounts: imageAccounts,
);

/// Una cuenta de imágenes de Gemini que [state].
ImageSide geminiImages({
  String id = 'g',
  ImageCapabilityState state = ImageCapabilityState.can,
  ImageFailure? reason,
}) => ImageSide(
  account: IllustrationAccount(
    id: id,
    provider: IllustrationProvider.gemini,
    label: id == 'g' ? 'Personal' : 'Trabajo',
    addedAt: DateTime.utc(2026, 10, 28),
  ),
  capability: ImageCapability(state: state, reason: reason),
  model: 'gemini-nano-banana-2.1',
  modelLabel: 'Nano Banana 2.1',
);

/// Lo de una prueba de Repasar: la app con su router de verdad sobre una base
/// en memoria, la cola de mentira y la estimación fija.
class RepasarHarness {
  RepasarHarness._(this.library, this.queue, this.estimates);

  final LibraryHarness library;
  final FakeCreationQueue queue;

  /// Lo que se le pidió a la estimación, en orden.
  final List<CreationEstimateRequest> estimates;

  /// Cómo contesta la estimación; se puede cambiar en cada prueba.
  static CreationEstimate Function(CreationEstimateRequest) estimate =
      fakeEstimate;

  ProviderContainer get container => library.container;

  static Future<RepasarHarness> create({
    List<CreationKindSpec> specs = const [],
    CreationSharer? sharer,
    int materialChars = 9000,

    /// Los temas sugeridos de la hoja («+ Moisés y Faraón»).
    List<String> suggestedTopics = const ['Moisés y Faraón', 'Alianza'],

    /// Los de la prueba, además de los de siempre: el servicio de
    /// ilustraciones de mentira de un tipo, por ejemplo.
    List<Override> overrides = const [],
  }) async {
    estimate = fakeEstimate;
    final estimates = <CreationEstimateRequest>[];
    late FakeCreationQueue queue;
    final library = await LibraryHarness.create(
      extraOverrides: [
        creationQueueProvider.overrideWith(
          (ref) => queue = FakeCreationQueue(
            ref.read(studyCreationRepositoryProvider),
          ),
        ),
        creationKindSpecsProvider.overrideWithValue(specs),
        creationSharerProvider.overrideWithValue(sharer),
        // El armado real corta en otro hilo: acá, un material fijo de
        // [materialChars] caracteres por fuente.
        creationSheetMaterialProvider.overrideWith(
          (ref, request) async => CreationMaterial(
            mode: CreationMaterialMode.fullText,
            text: 'x' * (materialChars * request.sourceIds.ids.length),
            sources: [
              for (final id in request.sourceIds.ids)
                CreationMaterialSource(
                  documentId: id,
                  title: id,
                  chars: materialChars,
                ),
            ],
          ),
        ),
        creationEstimateProvider.overrideWith((ref, request) {
          estimates.add(request);
          return estimate(request);
        }),
        creationSuggestedTopicsProvider.overrideWith(
          (ref, scope) async => suggestedTopics,
        ),
        ...overrides,
      ],
    );
    // La cola se arma al pedirla: así queda a mano desde el principio.
    library.container.read(creationQueueProvider);
    return RepasarHarness._(library, queue, estimates);
  }

  StudyCreationRepository get creations =>
      container.read(studyCreationRepositoryProvider);

  /// Un documento procesado [id] titulado [title], con [cards] tarjetas.
  Future<void> processed(
    String id,
    String title, {
    int cards = 0,
    String? sourceItemId,
  }) async {
    await insertProcessedRows(
      library.database,
      id: id,
      title: title,
      sourceItemId: sourceItemId,
    );
    for (var i = 0; i < cards; i++) {
      await container
          .read(flashcardRepositoryProvider)
          .create(itemId: id, front: '¿$title $i?', back: 'R $i');
    }
  }

  /// Una creación de [kind] sobre [scope] con [sources], guardada como la
  /// dejaría la hoja; [status] la lleva a ese estado.
  Future<StudyCreation> creation(
    StudyCreationKind kind, {
    CreationScope scope = const CreationScope.allProcessed(),
    List<String> sources = const [],
    CreationStatus status = CreationStatus.ready,
    String? title,
    double? progress,
    CreationStep step = CreationStep.writing,
    CreationFailure failure = CreationFailure.modelUnavailable,
    bool runNow = true,
    Map<String, Object?> options = const {},
  }) async {
    final created = (await creations.create(
      CreationRequest(
        kind: kind,
        scope: scope,
        sourceIds: sources,
        runNow: runNow,
        options: options,
      ),
    )).getOrElse((f) => throw StateError('$f'));
    final id = created.id;
    switch (status) {
      case CreationStatus.queued:
        break;
      case CreationStatus.generating:
        await creations.markGenerating(id, modelName: 'Gemini');
        await creations.reportProgress(id, progress: progress, step: step);
      case CreationStatus.ready:
        if (!kind.isLiveView) {
          await creations.complete(
            id,
            title: title ?? 'Creación ${kind.storageKey}',
            content: '{}',
          );
        } else if (title != null) {
          await creations.rename(id, title);
        }
      case CreationStatus.failed:
        await creations.fail(id, failure);
    }
    return (await creations.find(id)).getOrElse((f) => throw StateError('$f'))!;
  }

  /// La app entera con su router, en [theme], con la letra por [textScale] y
  /// sin animaciones —como pide la persona en el sistema—.
  Widget app({
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) {
    container.read(vaultSessionControllerProvider.notifier).markUnlocked();
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: theme.theme,
          darkTheme: theme.darkTheme,
          themeMode: theme.mode,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(goRouterProvider),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }

  /// Abre Repasar en un teléfono de [size].
  Future<void> openRepasar(
    WidgetTester tester, {
    Size size = const Size(420, 1600),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
    String location = '/review',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(theme: theme, textScale: textScale));
    await tester.pumpAndSettle();
    library.goTo(location);
    await tester.pumpAndSettle();
  }

  /// Lo elegido en el selector.
  CreationScope get scope => container.read(repasarScopeProvider);
}
