import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_document_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_study_analysis.dart';
import '../../../../support/memory_study_repository.dart';

void main() {
  final es = AppLocalizationsEs();
  const content =
      'La revolución industrial cambió todo. Nada más.\n\n'
      'Las fábricas usaban vapor.';
  const text = (renditionId: 'r1', content: content, markdown: true);

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
  }) async {
    repository = MemoryStudyRepository(study);
    analysis = FakeStudyAnalysis();
    container = ProviderContainer(
      overrides: [
        studyRepositoryProvider.overrideWithValue(repository),
        studyAnalysisProvider.overrideWith((ref, id) => analysis),
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
    testWidgets('Resumir prende el resumen y analiza lo que falta, con el '
        'texto y su forma; tocarlo de nuevo lo apaga', (tester) async {
      await pump(tester);

      await tap(tester, 'study-toggle-summary');
      expect(view().layer, StudyLayer.summary);
      expect(analysis.starts, [(content: content, markdown: true)]);

      await tap(tester, 'study-toggle-summary');
      expect(view().layer, isNull);
      expect(analysis.starts, hasLength(1));
    });

    testWidgets('Sintetizar reemplaza al resumen: nunca los dos encima', (
      tester,
    ) async {
      await pump(tester, study: analyzed);

      await tap(tester, 'study-toggle-summary');
      await tap(tester, 'study-toggle-synthesis');

      expect(view().layer, StudyLayer.synthesis);
    });

    testWidgets('con todo analizado no se vuelve a pedir', (tester) async {
      await pump(tester, study: analyzed);

      await tap(tester, 'study-toggle-summary');

      expect(view().layer, StudyLayer.summary);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('mientras analiza, otro toque no pide otra pasada', (
      tester,
    ) async {
      await pump(tester);
      analysis.shown = const StudyAnalysisRunning(null);

      await tester.tap(find.byKey(const Key('study-toggle-summary')));
      await tester.pump();

      expect(analysis.starts, isEmpty);
    });

    testWidgets('sin el modelo listo, lo avisa y no analiza nada', (
      tester,
    ) async {
      await pump(tester, status: const LanguageModelNeedsDownload());

      await tap(tester, 'study-toggle-summary');

      expect(find.text(es.studyModelRequired), findsOneWidget);
      expect(analysis.starts, isEmpty);
    });

    testWidgets('Palabras clave las muestra y analiza; el lápiz las elige', (
      tester,
    ) async {
      await pump(tester);

      await tap(tester, 'study-toggle-keywords');
      expect(view().keywords, isTrue);
      expect(analysis.starts, hasLength(1));

      await tap(tester, 'study-toggle-pick');
      expect(view().picking, isTrue);
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

      expect(find.text(es.studyAnalyzing(3, 12)), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 2 / 12);

      await tester.tap(find.text(es.studyStop));
      expect(analysis.stops, 1);
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

    testWidgets('analizado pero sin nada de una clase, lo dice', (
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
      for (final title in [
        es.studyExtractSummary,
        es.studyExtractSynthesis,
        es.studyExtractKeywords,
      ]) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      // Ninguna se abre: no hay nada que copiar.
      expect(find.text(es.studyCopy), findsNothing);
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
