import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/creation_cost_estimator.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide.dart';
import 'package:sinapsis/features/creations/presentation_deck/domain/slide_deck.dart';
import 'package:sinapsis/features/creations/presentation_kind/domain/presentation_content.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/processed_rows.dart';
import '../../presentation/repasar_harness.dart'
    show fakeEstimate, geminiImages;
import 'presentation_fakes.dart';

/// Lo de una prueba de pantalla de la Presentación (F43, paso 11): la app
/// entera con su router, la cola de crear de verdad y la Presentación
/// registrada como en la app, sobre una base en memoria; un modelo de
/// lenguaje y una IA de imágenes de mentira, y la estimación fija.
class PresentationHarness {
  PresentationHarness._(this.library, this.writer, this.images, this.estimates);

  final LibraryHarness library;
  final FakeDeckWriter writer;
  final FakeIllustrations images;

  /// Lo que se le pidió a la estimación, en orden.
  final List<CreationEstimateRequest> estimates;

  /// Cómo contesta la estimación: con Gemini que escribe y una cuenta que
  /// dibuja.
  static CreationEstimate Function(CreationEstimateRequest) estimate =
      _withImages;

  static CreationEstimate _withImages(CreationEstimateRequest request) =>
      fakeEstimate(request, imageAccounts: [geminiImages()]);

  ProviderContainer get container => library.container;

  StudyCreationRepository get creations =>
      container.read(studyCreationRepositoryProvider);

  CreationIllustrationStore get files =>
      CreationIllustrationStore(library.files);

  static Future<PresentationHarness> create() async {
    estimate = _withImages;
    final estimates = <CreationEstimateRequest>[];
    final writer = FakeDeckWriter(reply: (_) => deckJson(template: 'aurora'));
    final images = FakeIllustrations();
    final library = await LibraryHarness.create(
      extraOverrides: [
        structuredWriterProvider.overrideWithValue(writer),
        languageModelStatusCheckProvider.overrideWithValue(
          ({bool background = false}) async =>
              const LanguageModelReady(provider: AiProvider.gemini),
        ),
        languageModelNameProvider.overrideWithValue(() => 'Gemini 3.8 Flash'),
        illustrationServiceProvider.overrideWithValue(images),
        creationEstimateProvider.overrideWith((ref, request) {
          estimates.add(request);
          return estimate(request);
        }),
        // El armado de la hoja corta en otro hilo: acá, uno fijo.
        creationSheetMaterialProvider.overrideWith(
          (ref, request) async => CreationMaterial(
            mode: CreationMaterialMode.fullText,
            text: 'x' * 9000,
            sources: [
              for (final id in request.sourceIds.ids)
                CreationMaterialSource(documentId: id, title: id, chars: 9000),
            ],
          ),
        ),
      ],
    );
    return PresentationHarness._(library, writer, images, estimates);
  }

  /// Un documento procesado [id] titulado [title], con texto para leer.
  Future<void> processed(String id, String title) => insertProcessedRows(
    library.database,
    id: id,
    title: title,
    parts: const {
      ProcessedSection.text: [
        'Moisés guía al pueblo fuera de Egipto. El mar se abre.',
        'En el Sinaí se sella la alianza.',
      ],
    },
  );

  /// Una presentación lista con [deck] y [options]; [illustrated] son las
  /// diapositivas que ya tienen su ilustración guardada, y [misses], las que
  /// no salieron.
  Future<StudyCreation> ready(
    SlideDeck deck, {
    Map<String, Object?> options = const {},
    List<int> illustrated = const [],
    List<IllustrationMiss> misses = const [],
    String sourceId = 'd1',
  }) async {
    final created = (await creations.create(
      CreationRequest(
        kind: StudyCreationKind.presentation,
        scope: const CreationScope.allProcessed(),
        sourceIds: [sourceId],
        options: options,
      ),
    )).getOrElse((f) => throw StateError('$f'));
    var content = PresentationContent(
      deck: deck,
      misses: misses,
      illustrationAccount: 'Personal',
    );
    for (final slide in illustrated) {
      final path = await files.save(
        creationId: created.id,
        slotId: 'diapositiva-${slide + 1}',
        bytes: tinyPng(slide),
        mimeType: 'image/png',
      );
      content = content.withIllustration(slide, path);
    }
    await creations.complete(
      created.id,
      title: deck.title,
      content: content.encode(),
    );
    return (await creations.find(
      created.id,
    )).getOrElse((f) => throw StateError('$f'))!;
  }

  Future<StudyCreation> stored(String id) async =>
      (await creations.find(id)).getOrElse((f) => throw StateError('$f'))!;

  /// La app entera con su router, en [theme], con la letra por [textScale] y
  /// sin animaciones salvo que se pidan.
  Widget app({
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
    bool animations = false,
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
              disableAnimations: !animations,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }

  /// Abre la app en [location] en un teléfono de [size].
  Future<void> open(
    WidgetTester tester,
    String location, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
    bool animations = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(theme: theme, textScale: textScale, animations: animations),
    );
    await tester.pumpAndSettle();
    library.goTo('/review');
    await tester.pumpAndSettle();
    if (location != '/review') {
      library.pushTo(location);
      await tester.pumpAndSettle();
    }
  }

  /// Abre el visor de [creation].
  Future<void> openViewer(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => open(
    tester,
    '/creations/${creation.id}',
    size: size,
    theme: theme,
    textScale: textScale,
  );
}

/// Un mazo de cinco diapositivas con notas: portada ilustrable, viñetas,
/// cifra, imagen con texto y cierre.
SlideDeck viewerDeck({DeckFormat format = DeckFormat.presenter}) => SlideDeck(
  title: 'Éxodo: liberación y alianza',
  format: format,
  slides: const [
    Slide.cover(
      title: 'Éxodo: liberación y alianza',
      kicker: 'Estudio',
      illustrationPrompt: 'El mar abierto',
      speakerNotes: 'Hoy recorremos el Éxodo.',
    ),
    Slide.bullets(
      title: 'Por qué importa',
      bullets: ['Es el relato fundante', 'Une liberación y alianza'],
      speakerNotes: 'Primero, por qué importa.',
    ),
    Slide.bigNumber(
      value: '40',
      label: 'años en el desierto',
      illustrationPrompt: 'Un desierto',
    ),
    Slide.imageText(
      title: 'El Sinaí',
      body: 'La alianza se sella al pie del monte.',
      illustrationPrompt: 'Una montaña',
      speakerNotes: 'El centro del libro.',
    ),
    Slide.closing(
      title: 'Lo que hay que llevarse',
      takeaways: ['La libertad tiene un para qué'],
    ),
  ],
);

/// Las opciones de una presentación «Del presentador» con ilustraciones.
const presenterOptions = <String, Object?>{
  CreationOptionValues.format: CreationOptionValues.presenter,
  CreationOptionValues.illustrations: true,
};
