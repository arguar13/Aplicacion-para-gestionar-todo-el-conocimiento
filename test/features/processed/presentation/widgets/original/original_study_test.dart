import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_original_screen.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_study_analysis.dart';
import '../../../../../support/library_harness.dart';
import '../../processed_ui_fixture.dart';

/// Los botones de estudio del original de un documento procesado (F43, paso
/// 15): el original a la vista en el documento (M3), y marcar en él el
/// resumen, la síntesis y las palabras clave, con la IA o a mano (M5).
void main() {
  final es = AppLocalizationsEs();
  const text = 'La república romana cayó. César cruzó el Rubicón.';
  const add = OriginalEdit(ProcessedChange.add);
  late LibraryHarness harness;
  late Map<String, FakeStudyAnalysis> analyses;

  setUp(() async {
    analyses = {};
    harness = await LibraryHarness.create(
      extraOverrides: [
        studyAnalysisProvider.overrideWith(
          (ref, id) => analyses[id] = FakeStudyAnalysis(renditionId: id),
        ),
        languageModelStatusCheckProvider.overrideWithValue(
          ({bool background = false}) async =>
              const LanguageModelReady(provider: AiProvider.gemma),
        ),
      ],
    );
  });

  /// Un documento de texto con su copia del original y, si se pide, el
  /// resumen y una palabra clave traídos de la fuente.
  Future<String> processDocument({
    String id = 'roma',
    bool withMarks = false,
  }) async {
    await harness.saveTextSource(
      id,
      title: 'Roma',
      kind: SourceKind.document,
      originalName: 'notas.txt',
      originalBytes: text.codeUnits,
    );
    if (!withMarks) return harness.process(id, const {}, original: add);
    await harness.addSummarySentence(id, text, 'César cruzó el Rubicón.');
    await harness.addSummarySentence(
      id,
      text,
      'república',
      kind: StudyMarkKind.keyword,
    );
    return harness.process(id, {
      ProcessedSection.summary: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
      ProcessedSection.keywords: SectionEdit.add(
        const SectionInput.fromSource(),
      ),
    }, original: add);
  }

  Future<void> openDocument(WidgetTester tester, String id) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
    expect(find.byType(ProcessedDocumentScreen), findsOneWidget);
  }

  Future<void> openOriginal(WidgetTester tester, String id) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.processedOriginal(id));
    expect(find.byType(ProcessedOriginalScreen), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  String stateOf(WidgetTester tester, StudyMarkKind kind) => tester
      .widget<Text>(find.byKey(Key('original-study-state-${kind.name}')))
      .data!;

  StudyView viewOf(String id) => harness.container.read(
    studyViewProvider(processedOriginalStudyKeyFor(id)),
  );

  List<String> hiddenOf(String id) =>
      harness.container
          .read(sharedPreferencesProvider)
          .getStringList(ProcessedOriginalLayers.keyOf(id)) ??
      const [];

  group('el original a la vista en el documento (M3)', () {
    testWidgets('arriba los botones de estudio, el original en su marco como '
        'en la Biblioteca, y debajo qué es, cuánto ocupa y cuándo se '
        'copió', (tester) async {
      final id = await processDocument(withMarks: true);
      await openDocument(tester, id);

      final bar = find.byKey(const Key('original-study-bar'));
      final preview = find.byType(DocumentFirstPagePreview);
      final details = find.byKey(const Key('processed-original-details'));
      expect(bar, findsOneWidget);
      expect(preview, findsOneWidget);
      expect(details, findsOneWidget);
      expect(
        tester.getTopLeft(bar).dy,
        lessThan(tester.getTopLeft(preview).dy),
      );
      expect(
        tester.getTopLeft(preview).dy,
        lessThan(tester.getTopLeft(details).dy),
      );
      final line = tester.widget<Text>(
        find.descendant(of: details, matching: find.byType(Text)),
      );
      expect(line.data, startsWith(es.processedOriginalKindDocument));
      expect(line.data, contains('copiado el'));
      // Lo marcado se pinta también en la primera página.
      final study = tester.widget<DocumentFirstPagePreview>(preview).study!;
      expect(study.renditionId, processedOriginalStudyKeyFor(id));
    });

    testWidgets('tocar la hoja abre el original entero, con los mismos '
        'botones', (tester) async {
      final id = await processDocument(withMarks: true);
      await openDocument(tester, id);

      await tester.tap(find.byType(DocumentFirstPagePreview));
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedOriginalScreen), findsOneWidget);
      expect(find.byType(DocumentReaderView), findsOneWidget);
      expect(find.byKey(const Key('original-study-bar')), findsOneWidget);
    });

    testWidgets('sin copia del original no hay nada que ver', (tester) async {
      await harness.saveTextSource('roma', title: 'Roma');
      final id = await harness.processTextAndNotes('roma');
      await openDocument(tester, id);

      expect(find.byKey(const Key('processed-original-section')), findsNothing);
      expect(find.byKey(const Key('original-study-bar')), findsNothing);
    });
  });

  group('los botones de estudio (M5)', () {
    testWidgets('cada uno con su estado y cuántas marcas tiene: hecho con su '
        'número, o sin hacer; y la leyenda con los dos juntos', (tester) async {
      final id = await processDocument(withMarks: true);
      await openOriginal(tester, id);

      expect(
        stateOf(tester, StudyMarkKind.summary),
        es.f43OrigStateDone('summary'),
      );
      expect(stateOf(tester, StudyMarkKind.synthesis), es.f43OrigStateNone);
      expect(
        stateOf(tester, StudyMarkKind.keyword),
        es.f43OrigStateDone('keyword'),
      );
      for (final kind in [StudyMarkKind.summary, StudyMarkKind.keyword]) {
        expect(
          find.descendant(
            of: find.byKey(Key('original-study-${kind.name}')),
            matching: find.text('· 1'),
          ),
          findsOneWidget,
          reason: kind.name,
        );
        expect(
          find.byKey(Key('original-study-more-${kind.name}')),
          findsOneWidget,
        );
      }
      // Sin marcas no hay menú: no hay qué rehacer, ocultar ni borrar.
      expect(
        find.byKey(const Key('original-study-more-synthesis')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('original-study-legend-both')),
        findsOneWidget,
      );
    });

    testWidgets('sin marcas, el botón abre la hoja con «Con IA» —el modelo y '
        'lo que consume— y «A mano»; la ✕ la cierra sin tocar nada', (
      tester,
    ) async {
      final id = await processDocument();
      await openOriginal(tester, id);

      await tap(tester, 'original-study-synthesis');

      final sheet = find.byKey(const Key('original-study-choice-synthesis'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('original-study-choice-ai')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('original-study-choice-manual')),
        ),
        findsOneWidget,
      );
      expect(find.text(es.f43OrigChoiceAi), findsOneWidget);
      expect(find.text(es.f43OrigChoiceManual), findsOneWidget);
      expect(
        find.byKey(const Key('ai-capability-card')).evaluate().length +
            find
                .byKey(const Key('original-study-estimating'))
                .evaluate()
                .length,
        1,
      );

      await tester.tap(find.byTooltip(es.f43OrigClose));
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
      expect(analyses[processedStudyKeyFor(id)]?.starts ?? const [], isEmpty);
      expect(viewOf(id).pick, isNull);
    });

    testWidgets('«Con IA» analiza el texto propio del documento con el modelo '
        'elegido, y lo prende en el original', (tester) async {
      final id = await processDocument();
      await openOriginal(tester, id);

      await tap(tester, 'original-study-synthesis');
      await tap(tester, 'original-study-choice-ai');

      final analysis = analyses[processedStudyKeyFor(id)]!;
      expect(analysis.starts, hasLength(1));
      expect(analysis.starts.single.content, text);
      expect(analysis.starts.single.itemId, id);
      expect(viewOf(id).synthesis, isTrue);
    });

    testWidgets('mientras la IA marca, cada botón dice su avance —sin girar— y '
        'tocarlo prende o apaga en vez de volver a ofrecer', (tester) async {
      final id = await processDocument();
      await openOriginal(tester, id);
      await tap(tester, 'original-study-summary');
      await tap(tester, 'original-study-choice-ai');

      analyses[processedStudyKeyFor(id)]!.shown = const StudyAnalysisRunning(
        StudyProgress(partsDone: 1, partsTotal: 4),
      );
      await tester.pumpAndSettle();

      for (final kind in StudyMarkKind.values) {
        expect(stateOf(tester, kind), es.f45S4StateWorking(25));
      }
      // Una barra que se llena, en cada ficha (F45, paso 4).
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('original-study-progress-synthesis')),
      );
      expect(bar.value, 0.25);
      expect(find.byKey(const Key('study-progress')), findsOneWidget);

      await tap(tester, 'original-study-synthesis');
      expect(
        find.byKey(const Key('original-study-choice-synthesis')),
        findsNothing,
      );
      expect(viewOf(id).synthesis, isFalse);
    });

    testWidgets('«A mano» desde el documento pasa a elegir y abre el original '
        'entero; tocar una oración la suma, y «Listo» termina', (tester) async {
      final id = await processDocument();
      await openDocument(tester, id);

      await tap(tester, 'original-study-synthesis');
      await tap(tester, 'original-study-choice-manual');

      expect(find.byType(ProcessedOriginalScreen), findsOneWidget);
      expect(viewOf(id).pick, StudyMarkKind.synthesis);
      expect(find.byKey(const Key('original-study-picking')), findsOneWidget);
      expect(find.text(es.f43OrigPickHintSentences), findsOneWidget);

      // Lo que hace el lector al tocar: la oración de ahí va a la síntesis.
      final reader = tester.widget<DocumentReaderView>(
        find.byType(DocumentReaderView),
      );
      final bar = find.byType(OriginalStudyBar);
      // Guardar pasa por el texto propio del documento, que se arma fuera
      // del reloj de la prueba.
      await tester.runAsync(
        () => pickStudyAt(
          tester.element(bar) as WidgetRef,
          tester.element(bar),
          renditionId: reader.study!.renditionId,
          content: reader.study!.content,
          markdown: reader.study!.markdown,
          offset: text.indexOf('César'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        stateOf(tester, StudyMarkKind.synthesis),
        es.f43OrigStateDone('synthesis'),
      );
      final study = await harness.container.read(
        documentStudyProvider(processedStudyKeyFor(id)).future,
      );
      expect(
        [
          for (final m in study.of(StudyMarkKind.synthesis))
            text.substring(m.start, m.end),
        ],
        ['César cruzó el Rubicón.'],
      );

      await tap(tester, 'original-study-pick-done');
      expect(viewOf(id).pick, isNull);
      expect(viewOf(id).synthesis, isTrue);
      expect(find.byKey(const Key('original-study-picking')), findsNothing);
    });

    testWidgets('con marcas, tocar el botón apaga y prende el resaltado, y '
        'queda recordado para ese documento', (tester) async {
      final id = await processDocument(withMarks: true);
      await openOriginal(tester, id);
      expect(viewOf(id).summary, isTrue);

      await tap(tester, 'original-study-summary');

      expect(viewOf(id).summary, isFalse);
      expect(
        stateOf(tester, StudyMarkKind.summary),
        es.f43OrigStateHidden('summary'),
      );
      expect(hiddenOf(id), [StudyMarkKind.summary.name]);

      await tap(tester, 'original-study-summary');

      expect(viewOf(id).summary, isTrue);
      expect(hiddenOf(id), isEmpty);
    });

    testWidgets('las palabras clave, hechas, se ven por defecto; ocultarlas '
        'desde el menú queda recordado al volver a abrir, solo en ese '
        'documento', (tester) async {
      final id = await processDocument(withMarks: true);
      // Otro documento, con su original: lo oculto en uno no lo oculta en el
      // otro.
      final other = await processDocument(id: 'otra');
      await openOriginal(tester, id);
      expect(viewOf(id).keywords, isTrue);

      // Mantenerlo apretado abre el mismo menú que el ⋯.
      await tester.longPress(find.byKey(const Key('original-study-keyword')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('original-study-menu-keyword')),
        findsOneWidget,
      );
      await tap(tester, 'original-study-menu-hide');

      expect(viewOf(id).keywords, isFalse);
      expect(hiddenOf(id), [StudyMarkKind.keyword.name]);
      // Lo leen las demás pantallas del documento (los visores de Repasar).
      expect(
        harness.container.read(processedKeywordsShownProvider(id)),
        isFalse,
      );
      expect(
        harness.container.read(processedKeywordsShownProvider(other)),
        isTrue,
      );

      // Se vuelve a abrir: sigue oculto. El otro documento, no.
      await goAndSettle(tester, harness, RoutePaths.processed);
      await pushAndSettle(tester, harness, RoutePaths.processedOriginal(id));
      expect(viewOf(id).keywords, isFalse);
      expect(
        stateOf(tester, StudyMarkKind.keyword),
        es.f43OrigStateHidden('keyword'),
      );
      await goAndSettle(tester, harness, RoutePaths.processed);
      await pushAndSettle(tester, harness, RoutePaths.processedOriginal(other));
      expect(viewOf(other).keywords, isTrue);
      expect(hiddenOf(other), isEmpty);

      // Y desde el menú se vuelven a mostrar.
      await goAndSettle(tester, harness, RoutePaths.processed);
      await pushAndSettle(tester, harness, RoutePaths.processedOriginal(id));
      await tap(tester, 'original-study-more-keyword');
      await tap(tester, 'original-study-menu-show');
      expect(viewOf(id).keywords, isTrue);
      expect(hiddenOf(id), isEmpty);
    });

    testWidgets('el menú: «Borrar las marcas» pregunta y las borra del '
        'documento; el botón vuelve a «Sin hacer»', (tester) async {
      final id = await processDocument(withMarks: true);
      await openOriginal(tester, id);

      await tap(tester, 'original-study-more-summary');
      await tap(tester, 'original-study-menu-clear');
      expect(find.text(es.f43OrigClearTitle('summary')), findsOneWidget);
      await tap(tester, 'original-study-clear-confirm');

      expect(stateOf(tester, StudyMarkKind.summary), es.f43OrigStateNone);
      final parts =
          (await harness.container
                  .read(processedRepositoryProvider)
                  .partsOf(id, sections: {ProcessedSection.summary}))
              .getRight()
              .toNullable()!;
      expect(parts, isEmpty);
      // Las palabras clave siguen.
      expect(
        stateOf(tester, StudyMarkKind.keyword),
        es.f43OrigStateDone('keyword'),
      );
    });

    testWidgets('el menú: «Rehacer con IA» dice lo que hace y consume, y al '
        'confirmar vuelve a analizar desde el principio', (tester) async {
      final id = await processDocument(withMarks: true);
      await openOriginal(tester, id);

      await tap(tester, 'original-study-more-summary');
      await tap(tester, 'original-study-menu-redoWithAi');
      expect(find.byKey(const Key('original-study-redo')), findsOneWidget);
      expect(find.text(es.f43OrigRedoBody), findsOneWidget);
      await tap(tester, 'original-study-redo-confirm');

      final analysis = analyses[processedStudyKeyFor(id)]!;
      expect(analysis.starts, hasLength(1));
      expect(analysis.starts.single.content, text);
    });

    testWidgets('«Retocar a mano» pasa a elegir lo de ese botón', (
      tester,
    ) async {
      final id = await processDocument(withMarks: true);
      await openOriginal(tester, id);

      await tap(tester, 'original-study-more-keyword');
      await tap(tester, 'original-study-menu-retouch');

      expect(viewOf(id).pick, StudyMarkKind.keyword);
      expect(find.text(es.f43OrigPickHintWords(4)), findsOneWidget);
    });
  });

  group('se ve bien', () {
    Future<void> phone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
    }

    testWidgets('en 360 dp con la letra al doble, ni el documento, ni el '
        'original, ni la hoja, ni el menú desbordan', (tester) async {
      final id = await processDocument(withMarks: true);
      await phone(tester);
      await pushAndSettle(tester, harness, RoutePaths.processedDocument(id));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('original-study-bar')), findsOneWidget);

      harness.container.read(goRouterProvider).go(RoutePaths.processed);
      await tester.pumpAndSettle();
      await pushAndSettle(tester, harness, RoutePaths.processedOriginal(id));
      expect(tester.takeException(), isNull);

      await tap(tester, 'original-study-synthesis');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('original-study-choice-synthesis')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip(es.f43OrigClose));
      await tester.pumpAndSettle();

      await tap(tester, 'original-study-more-summary');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('original-study-menu-clear')),
        findsOneWidget,
      );
    });
  });
}
