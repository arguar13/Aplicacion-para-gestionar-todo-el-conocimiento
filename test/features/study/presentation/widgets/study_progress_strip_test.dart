import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_progress_strip.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';

/// La franja de cómo va el análisis (F36, F39), sola: la de las fichas del
/// original, el mismo en Procesado y en la Biblioteca (F45, paso 7b), y la de
/// lo extraído en Repasar. Los botones que la acompañaban en la Biblioteca
/// —`StudyToggles`— salieron: la fuente se marca con las fichas de su
/// original (`original_source_study_test.dart`).
void main() {
  final es = AppLocalizationsEs();
  const content =
      'La revolución industrial cambió todo. Nada más.\n\n'
      'Las fábricas usaban vapor.';
  const text = (
    itemId: 'i1',
    renditionId: 'r1',
    content: content,
    markdown: true,
  );

  StudyMark mark(String id, StudyMarkKind kind, String part) {
    final start = content.indexOf(part);
    return StudyMark(
      id: id,
      kind: kind,
      origin: ContentOrigin.ai,
      start: start,
      end: start + part.length,
    );
  }

  final analyzed = DocumentStudy(
    marks: [
      mark(
        's1',
        StudyMarkKind.summary,
        'La revolución industrial cambió todo.',
      ),
      mark('k1', StudyMarkKind.keyword, 'revolución'),
      mark('y1', StudyMarkKind.synthesis, 'Las fábricas usaban vapor.'),
      mark('k2', StudyMarkKind.keyword, 'vapor'),
    ]..sort((a, b) => a.start.compareTo(b.start)),
    analyzedUntil: content.length,
    complete: true,
  );

  late ProviderContainer container;
  late MemoryStudyRepository repository;
  late FakeStudyAnalysis analysis;

  Future<void> pump(
    WidgetTester tester, {
    DocumentStudy study = DocumentStudy.notStarted,
    LanguageModelStatus status = const LanguageModelReady(
      provider: AiProvider.gemma,
    ),
  }) async {
    repository = MemoryStudyRepository(study);
    analysis = FakeStudyAnalysis();
    container = ProviderContainer(
      overrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        studyRepositoryProvider.overrideWithValue(repository),
        studyAnalysisProvider.overrideWith((ref, id) => analysis),
        chosenLanguageModelNameProvider.overrideWithValue('gemini-2.5-flash'),
        languageModelStatusCheckProvider.overrideWithValue(
          ({bool background = false}) async => status,
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: StudyProgressStrip(text: text)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('cómo va el análisis', () {
    testWidgets('la parte que va, su barra y Parar', (tester) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisRunning(null);
      // Sin saber cuánto va, la barra se mueve sin parar: no se asienta.
      await tester.pump();
      expect(find.text(es.studyPreparing), findsOneWidget);

      analysis.shown = const StudyAnalysisRunning(
        StudyProgress(partsDone: 2, partsTotal: 12),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.studyAnalyzingPercent(3, 12, 16)), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 2 / 12);

      await tester.tap(find.text(es.studyStop));
      expect(analysis.stops, 1);
    });

    testWidgets('con una parte hecha, dice el porcentaje y cuánto falta', (
      tester,
    ) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisRunning(
        StudyProgress(partsDone: 3, partsTotal: 12),
        remaining: Duration(minutes: 4, seconds: 10),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(es.studyAnalyzingEta(4, 12, 25, es.studyEtaMinutes(5))),
        findsOneWidget,
      );
    });

    testWidgets('si la IA se está reintentando, lo dice con el intento', (
      tester,
    ) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisRunning(
        StudyProgress(partsDone: 3, partsTotal: 12),
        retry: StudyRetry(
          attempt: 2,
          maxAttempts: 4,
          failure: CloudModelFailure.cutOff,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(es.aiRetrying(2, 4, es.lmFailureCutOff)),
        findsOneWidget,
      );
      expect(find.textContaining('Reintentando (2 de 4)'), findsOneWidget);
    });

    testWidgets('si se corta por la IA en la nube, dice qué pasó de verdad', (
      tester,
    ) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisFailed(
        CloudModelException(CloudModelFailure.timeout),
      );
      await tester.pumpAndSettle();

      expect(find.text(es.studyFailed), findsNothing);
      expect(find.text(es.studyFailedWhy(es.lmHelpTimeout)), findsOneWidget);
    });

    testWidgets('si se corta, lo dice, y Reintentar sigue desde ahí', (
      tester,
    ) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisFailed('sin conexión');
      await tester.pumpAndSettle();

      expect(find.text(es.studyFailed), findsOneWidget);
      await tester.tap(find.text(es.studyRetry));
      await tester.pumpAndSettle();

      expect(analysis.starts, hasLength(1));
      expect(find.text(es.studyFailed), findsNothing);
    });

    testWidgets('las partes que no se pudieron leer se cuentan, y Entendido '
        'cierra el aviso', (tester) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisDone(unreadParts: 2);
      await tester.pumpAndSettle();

      expect(find.text(es.studyUnreadParts(2)), findsOneWidget);
      await tester.tap(find.text(es.studyUnreadAcknowledge));
      await tester.pumpAndSettle();

      expect(find.text(es.studyUnreadParts(2)), findsNothing);
    });

    testWidgets('terminado sin problemas, no ocupa lugar', (tester) async {
      await pump(tester, study: analyzed);
      analysis.shown = const StudyAnalysisDone();
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(es.studyUnreadAcknowledge), findsNothing);
    });
  });
}
