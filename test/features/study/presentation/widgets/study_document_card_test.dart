import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';

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
    WidgetBuilder? extractedText,
    ExpansibleController? extractedTextController,
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
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudyDocumentCard(
                text: text,
                extractedText: extractedText,
                extractedTextController: extractedTextController,
                extractedTextSubtitle: 'Para buscar',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StudyView view() => container.read(studyViewProvider('r1'));

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('los tres botones', () {
    testWidgets('sin nada todavía, Resumir ofrece armarlo con el modelo '
        'elegido —por su nombre— o a mano; con la IA, lo prende y analiza el '
        'texto con su forma', (tester) async {
      await pump(tester);

      await tap(tester, 'study-toggle-summary');
      expect(find.byKey(const Key('study-suggestion-summary')), findsOneWidget);
      expect(find.text(es.studySuggestTitleSummary), findsOneWidget);
      expect(
        find.text(es.studySuggestSummarizeWith('Gemini 2.5 Flash')),
        findsOneWidget,
      );
      // Todavía no se prendió nada: se eligió el camino recién.
      expect(view().summary, isFalse);
      expect(analysis.starts, isEmpty);

      await tap(tester, 'study-suggest-ai');
      expect(find.byKey(const Key('study-suggestion-summary')), findsNothing);
      expect(view().summary, isTrue);
      expect(view().picking, isFalse);
      expect(analysis.starts, [(content: content, markdown: true)]);
    });

    testWidgets('a mano, lo prende y pasa a elegirlo, avisa qué se elige y '
        'Listo lo termina; no analiza nada', (tester) async {
      await pump(tester);

      await tap(tester, 'study-toggle-synthesis');
      await tap(tester, 'study-suggest-manual');

      expect(view().synthesis, isTrue);
      expect(view().pick, StudyMarkKind.synthesis);
      expect(analysis.starts, isEmpty);
      expect(
        find.text('${es.studyPickingSynthesis} · ${es.studyPickingDone}'),
        findsOneWidget,
      );

      await tap(tester, 'study-pick-done');
      expect(view().pick, isNull);
      expect(view().synthesis, isTrue);
      expect(find.byKey(const Key('study-pick-done')), findsNothing);
    });

    testWidgets('cerrar la sugerencia sin elegir no prende nada', (
      tester,
    ) async {
      await pump(tester);

      await tap(tester, 'study-toggle-summary');
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('study-suggestion-summary')), findsNothing);
      expect(view(), const StudyView());
      expect(analysis.starts, isEmpty);
    });

    testWidgets('con lo elegido a mano y el análisis sin empezar, prenderlo '
        'no arranca la IA sola', (tester) async {
      await pump(
        tester,
        study: const DocumentStudy(
          marks: [
            StudyMark(
              id: 'u1',
              kind: StudyMarkKind.summary,
              origin: ContentOrigin.user,
              start: 0,
              end: 37,
            ),
          ],
          analyzedUntil: 0,
          complete: false,
        ),
      );

      await tap(tester, 'study-toggle-summary');

      expect(find.byKey(const Key('study-suggestion-summary')), findsNothing);
      expect(view().summary, isTrue);
      expect(analysis.starts, isEmpty);

      await tap(tester, 'study-toggle-summary');
      expect(view().summary, isFalse);
    });

    testWidgets('con un análisis a mitad, prenderlo lo sigue', (tester) async {
      await pump(
        tester,
        study: DocumentStudy(
          marks: [
            mark(
              's1',
              StudyMarkKind.summary,
              'La revolución industrial cambió todo.',
            ),
          ],
          analyzedUntil: 40,
          complete: false,
        ),
      );

      // Le falta síntesis, pero un análisis a mitad la va a traer: no se
      // ofrece nada, sigue.
      await tap(tester, 'study-toggle-synthesis');

      expect(find.byKey(const Key('study-suggestion-synthesis')), findsNothing);
      expect(view().synthesis, isTrue);
      expect(analysis.starts, hasLength(1));
    });

    testWidgets('los tres se prenden cada uno por su lado: juntos, de a uno, '
        'de a dos o ninguno (F39)', (tester) async {
      await pump(tester, study: analyzed);

      await tap(tester, 'study-toggle-summary');
      await tap(tester, 'study-toggle-synthesis');
      await tap(tester, 'study-toggle-keywords');
      expect(
        view(),
        const StudyView(summary: true, synthesis: true, keywords: true),
      );

      await tap(tester, 'study-toggle-summary');
      expect(view(), const StudyView(synthesis: true, keywords: true));

      await tap(tester, 'study-toggle-keywords');
      expect(view(), const StudyView(synthesis: true));

      await tap(tester, 'study-toggle-synthesis');
      expect(view(), const StudyView());
    });

    testWidgets('apagar el resaltado que se elige a mano deja de elegirlo; '
        'prender otro, no; las palabras clave se siguen eligiendo', (
      tester,
    ) async {
      await pump(tester, study: analyzed);
      container.read(studyViewProvider('r1').notifier).state = const StudyView(
        summary: true,
        pick: StudyMarkKind.summary,
      );

      await tap(tester, 'study-toggle-synthesis');
      expect(view().pick, StudyMarkKind.summary);

      await tap(tester, 'study-toggle-summary');
      expect(view().pick, isNull);

      await tap(tester, 'study-toggle-pick');
      await tap(tester, 'study-toggle-synthesis');
      expect(view().pick, StudyMarkKind.keyword);
    });

    testWidgets('con todo analizado no se vuelve a pedir', (tester) async {
      await pump(tester, study: analyzed);

      await tap(tester, 'study-toggle-summary');

      expect(view().summary, isTrue);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('analizado todo y sin nada de una clase, solo queda elegirlo '
        'a mano: pedírselo a la IA daría lo mismo', (tester) async {
      await pump(
        tester,
        study: DocumentStudy(
          marks: [
            mark(
              's1',
              StudyMarkKind.summary,
              'La revolución industrial cambió todo.',
            ),
          ],
          analyzedUntil: content.length,
          complete: true,
        ),
      );

      await tap(tester, 'study-toggle-keywords');

      expect(find.byKey(const Key('study-suggestion-keyword')), findsOneWidget);
      expect(find.byKey(const Key('study-suggest-ai')), findsNothing);
      await tap(tester, 'study-suggest-manual');
      expect(view().pick, StudyMarkKind.keyword);
      expect(view().showsKeywords, isTrue);
    });

    testWidgets('mientras analiza, otro toque no pide otra pasada ni ofrece '
        'nada', (tester) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisRunning(null);

      await tester.tap(find.byKey(const Key('study-toggle-summary')));
      await tester.pump();

      expect(find.byKey(const Key('study-suggestion-summary')), findsNothing);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('sin el modelo listo, elegir la IA lo avisa y no analiza '
        'nada', (tester) async {
      await pump(tester, status: const LanguageModelNeedsDownload());

      await tap(tester, 'study-toggle-summary');
      await tap(tester, 'study-suggest-ai');

      expect(find.text(es.studyModelRequired), findsOneWidget);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('Palabras clave: con la IA las muestra y analiza; el lápiz '
        'las elige', (tester) async {
      await pump(tester);

      await tap(tester, 'study-toggle-keywords');
      expect(find.text(es.studySuggestBodyKeywords(4)), findsOneWidget);
      await tap(tester, 'study-suggest-ai');
      expect(view().keywords, isTrue);
      expect(analysis.starts, hasLength(1));

      await tap(tester, 'study-toggle-pick');
      expect(view().pick, StudyMarkKind.keyword);
      expect(
        find.text('${es.studyPickingKeywords} · ${es.studyPickingDone}'),
        findsOneWidget,
      );
      await tap(tester, 'study-toggle-pick');
      expect(view().picking, isFalse);

      await tap(tester, 'study-toggle-keywords');
      expect(view().keywords, isFalse);
    });
  });

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

  group('Extraer', () {
    testWidgets('antes de analizar, cada fila dice cómo empezar', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(es.studyExtractStart), findsNWidgets(3));
    });

    testWidgets('analizado pero sin nada de una clase, lo dice; '
        'desplegada, mientras sigue el análisis avisa que va a aparecer ahí', (
      tester,
    ) async {
      await pump(
        tester,
        study: const DocumentStudy(
          marks: [],
          analyzedUntil: 10,
          complete: false,
        ),
      );

      expect(find.text(es.studyExtractEmpty), findsNWidgets(3));
      analysis.shown = const StudyAnalysisRunning(null);
      await tester.tap(find.text(es.studyExtractSummary));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(es.studyExtractRunning), findsOneWidget);
      // No hay nada que copiar.
      expect(find.text(es.studyCopy), findsNothing);
    });

    testWidgets('vacía y desplegada, ofrece armarlo: a mano, lo prende, pasa '
        'a elegirlo y despliega el texto donde se toca', (tester) async {
      final controller = ExpansibleController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        extractedText: (_) => const Text('el texto entero'),
        extractedTextController: controller,
      );

      await tester.tap(find.text(es.studyExtractKeywords));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('study-extract-keywords')),
          matching: find.byKey(const Key('study-suggestion-keyword')),
        ),
        findsOneWidget,
      );
      expect(find.text('el texto entero'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('study-suggest-manual')));
      await tap(tester, 'study-suggest-manual');

      expect(view().pick, StudyMarkKind.keyword);
      expect(view().showsKeywords, isTrue);
      expect(analysis.starts, isEmpty);
      expect(find.text('el texto entero'), findsOneWidget);

      // Terminado, lo elegido se sigue viendo.
      await tester.ensureVisible(find.byKey(const Key('study-pick-done')));
      await tap(tester, 'study-pick-done');
      expect(view().pick, isNull);
      expect(view().keywords, isTrue);
    });

    testWidgets('vacía y desplegada, con la IA analiza', (tester) async {
      await pump(tester);

      await tester.tap(find.text(es.studyExtractSummary));
      await tester.pumpAndSettle();
      await tap(tester, 'study-suggest-ai');

      expect(view().summary, isTrue);
      expect(analysis.starts, hasLength(1));
    });

    testWidgets('el resumen, con cuántas oraciones y palabras, como texto '
        'corrido, y se copia', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, study: analyzed);

      expect(
        find.text('${es.studySentenceCount(1)} · ${es.studyWordCount(5)}'),
        findsOneWidget,
      );
      expect(
        find.text('${es.studySentenceCount(1)} · ${es.studyWordCount(4)}'),
        findsOneWidget,
      );
      await tester.tap(find.text(es.studyExtractSummary));
      await tester.pumpAndSettle();

      expect(
        find.text('La revolución industrial cambió todo.'),
        findsOneWidget,
      );
      await tester.tap(find.text(es.studyCopy));
      await tester.pumpAndSettle();
      expect(copied, 'La revolución industrial cambió todo.');
      expect(find.text(es.studyCopied), findsOneWidget);
    });

    testWidgets('las palabras clave, como etiquetas en orden', (tester) async {
      await pump(tester, study: analyzed);

      expect(find.text(es.studyKeywordCount(2)), findsOneWidget);
      await tester.tap(find.text(es.studyExtractKeywords));
      await tester.pumpAndSettle();

      final chips = tester
          .widgetList<Chip>(find.byType(Chip))
          .map((c) => (c.label as Text).data);
      expect(chips, ['revolución', 'vapor']);
    });

    testWidgets('el texto extraído se arma recién al desplegarlo', (
      tester,
    ) async {
      var built = 0;
      await pump(
        tester,
        extractedText: (context) {
          built++;
          return const Text('El texto entero');
        },
      );

      expect(find.text('Para buscar'), findsOneWidget);
      expect(built, 0);
      await tester.tap(find.text(es.studyExtractText));
      await tester.pumpAndSettle();

      expect(built, greaterThan(0));
      expect(find.text('El texto entero'), findsOneWidget);
    });

    testWidgets('sin texto extraído —una página web—, no hay esa fila', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(es.studyExtractText), findsNothing);
    });
  });

  group('Volver a analizar', () {
    Future<void> open(WidgetTester tester) async {
      await tap(tester, 'study-menu');
      await tester.tap(find.byKey(const Key('study-reanalyze')));
      await tester.pumpAndSettle();
    }

    testWidgets('pregunta antes; al confirmar, borra lo estudiado y analiza '
        'de nuevo', (tester) async {
      await pump(tester, study: analyzed);

      await open(tester);
      expect(find.text(es.studyReanalyzeBody), findsOneWidget);
      await tap(tester, 'study-reanalyze-confirm');

      expect(repository.cleared, ['r1']);
      expect(analysis.starts, [(content: content, markdown: true)]);
    });

    testWidgets('al cancelar, no toca nada', (tester) async {
      await pump(tester, study: analyzed);

      await open(tester);
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(repository.cleared, isEmpty);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('sin el modelo listo, no borra nada', (tester) async {
      await pump(
        tester,
        study: analyzed,
        status: const LanguageModelNeedsDownload(),
      );

      await open(tester);
      await tap(tester, 'study-reanalyze-confirm');

      expect(repository.cleared, isEmpty);
      expect(find.text(es.studyModelRequired), findsOneWidget);
    });

    testWidgets('mientras analiza, no se ofrece', (tester) async {
      await pump(tester, study: analyzed);
      analysis.shown = const StudyAnalysisRunning(null);
      await tester.pump();

      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final item = tester.widget<PopupMenuItem<void>>(
        find.byKey(const Key('study-reanalyze')),
      );
      expect(item.enabled, isFalse);
    });
  });
}
