import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_study_text.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_marker.dart';
import 'package:sinapsis/features/study/domain/services/study_reply.dart';
import 'package:sinapsis/features/study/domain/services/study_sentences.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../support/fake_text_to_speech_service.dart';
import '../../../support/library_harness.dart';
import '../../processed/presentation/processed_ui_fixture.dart';
import '../presentation/repasar_harness.dart' show fakeEstimate;

/// Un modelo de mentira para el análisis de estudiar (F36): de cada parte, la
/// primera oración al resumen, la segunda a la síntesis y la primera palabra
/// de cada oración como palabra clave. Cuenta las partes que marcó.
class FirstSentenceMarker implements StudyMarker {
  int parts = 0;

  @override
  int get partCharBudget => 10000;

  @override
  Future<StudyPartOutcome> markPart({
    required String content,
    required List<StudySentence> part,
  }) async {
    parts++;
    return StudyPartOutcome(
      analyzed: part.length,
      marks: StudyPartMarks(
        summary: part.take(1).toList(),
        synthesis: part.skip(1).take(1).toList(),
        keywords: [
          for (final sentence in part)
            () {
              final space = content.indexOf(' ', sentence.start);
              final end = space < 0 || space > sentence.end
                  ? sentence.end
                  : space;
              return StudyWord(
                sentence.start,
                end,
                content.substring(sentence.start, end),
              );
            }(),
        ],
      ),
    );
  }
}

/// Lo de una prueba de los visores de extraer (F43, paso 7): la app con su
/// router de verdad sobre una base en memoria, la cola de crear de verdad, el
/// análisis de estudiar de verdad con un modelo de mentira y el lector en voz
/// alta con un motor de mentira.
class ExtractHarness {
  ExtractHarness._(this.library, this.marker);

  final LibraryHarness library;
  final FirstSentenceMarker marker;

  /// Si el modelo está listo para analizar.
  bool modelReady = true;

  /// La hora del repositorio de Procesado: la de verdad, salvo que la prueba
  /// la congele para que dos cambios caigan en el mismo instante.
  DateTime? frozenAt;

  ProviderContainer get container => library.container;
  FakeTextToSpeechService get tts => library.textToSpeechService;

  static Future<ExtractHarness> create() async {
    final marker = FirstSentenceMarker();
    late ExtractHarness harness;
    final library = await LibraryHarness.create(
      extraOverrides: [
        studyMarkerProvider.overrideWithValue(marker),
        languageModelStatusCheckProvider.overrideWithValue(
          ({bool background = false}) async => harness.modelReady
              ? const LanguageModelReady(provider: AiProvider.gemma)
              : const LanguageModelNeedsDownload(),
        ),
        creationEstimateProvider.overrideWith(
          (ref, request) => fakeEstimate(request),
        ),
        processedRepositoryProvider.overrideWith(
          (ref) => ProcessedRepositoryImpl(
            database: ref.watch(appDatabaseProvider),
            telemetry: ref.watch(telemetryServiceProvider),
            files: ref.watch(fileStoreProvider),
            clock: () => harness.frozenAt ?? DateTime.now(),
          ),
        ),
      ],
    );
    return harness = ExtractHarness._(library, marker);
  }

  /// Un documento procesado de la fuente [sourceId], con [text] entero en su
  /// sección «Texto». Devuelve su id.
  Future<String> document(
    String sourceId, {
    required String title,
    required String text,
  }) async {
    await library.saveTextSource(sourceId, title: title, text: text);
    return library.processTextAndNotes(sourceId);
  }

  /// El texto propio del documento [id].
  Future<ProcessedStudyText> own(String id) async =>
      (await container.read(processedRepositoryProvider).studyTextOf(id))
          .getOrElse((failure) => throw StateError('$failure'))!;

  /// Marca [passage] como [kind] en el documento [id], como lo hace el
  /// original al elegir a mano (M5): en sus marcas de estudiar.
  Future<void> mark(
    String id,
    String passage, {
    StudyMarkKind kind = StudyMarkKind.summary,
  }) async {
    final text = await own(id);
    final start = text.content.indexOf(passage);
    expect(start, isNonNegative, reason: passage);
    final saved = await container
        .read(studyRepositoryProvider)
        .addUserMark(
          renditionId: text.key,
          content: text.content,
          kind: kind,
          start: start,
          end: start + passage.length,
        );
    expect(saved.isRight(), isTrue, reason: '$saved');
  }

  /// Lo estudiado del documento [id]: sus marcas, la única fuente (M8).
  Future<DocumentStudy> study(String id) async =>
      container.read(studyRepositoryProvider).read((await own(id)).key);

  /// Una extracción de [kind] de [ids], creada por la cola de verdad, como la
  /// deja «Crear»: lista enseguida (decisión E).
  Future<StudyCreation> creation(
    StudyCreationKind kind,
    List<String> ids,
  ) async {
    final created = await container
        .read(creationQueueProvider)
        .create(
          CreationRequest(
            kind: kind,
            scope: ids.length == 1
                ? CreationScope.document(ids.single)
                : const CreationScope.allProcessed(),
            sourceIds: ids,
          ),
        );
    return created.getOrElse((failure) => throw StateError('$failure'));
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

  /// Abre el visor de [creation] en una pantalla de [size].
  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 1400),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(theme: theme, textScale: textScale));
    await tester.pumpAndSettle();
    library.pushTo(RoutePaths.creation(creation.id));
    await tester.pumpAndSettle();
  }
}

/// Lo que se ve pintado de [background] dentro de [within], tramo por tramo,
/// en orden: el rosa de las palabras clave, el amarillo de lo que suena.
List<String> paintedWith(
  WidgetTester tester,
  Color background, {
  Finder? within,
}) {
  final out = <String>[];
  final texts = within == null
      ? find.byType(RichText)
      : find.descendant(of: within, matching: find.byType(RichText));
  for (final rich in tester.widgetList<RichText>(texts)) {
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text != null &&
          span.style?.backgroundColor == background) {
        out.add(span.text!);
      }
      return true;
    });
  }
  return out;
}
