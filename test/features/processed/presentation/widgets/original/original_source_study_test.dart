import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_reader_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_study_analysis.dart';
import '../../../../../support/library_harness.dart';
import '../../processed_ui_fixture.dart';

/// El original de una fuente de la Biblioteca, **el mismo que en Procesado**
/// (F45, paso 7b, mejoras 15 y 16, decisión H): la vista previa del detalle
/// dice qué tiene marcado, y a pantalla completa lleva las mismas fichas y el
/// mismo lector. Marca sobre la fuente, por su propia clave, y lo oculto
/// queda recordado; de la Biblioteca no se borra nada de una vez.
void main() {
  final es = AppLocalizationsEs();
  const text = 'La república romana cayó. César cruzó el Rubicón.';
  const rendition = 'rend-roma';
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

  /// Una fuente de texto con su archivo y, si se pide, el resumen marcado.
  Future<void> saveSource({bool withSummary = false}) async {
    await harness.saveTextSource(
      'roma',
      title: 'Roma',
      kind: SourceKind.document,
      originalName: 'notas.txt',
      originalBytes: text.codeUnits,
    );
    if (withSummary) {
      await harness.addSummarySentence('roma', text, 'César cruzó el Rubicón.');
    }
  }

  Future<void> openOriginal(WidgetTester tester) async {
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));
    await tester.tap(find.byKey(const Key('embedded-viewer-read-as-book')));
    await tester.pumpAndSettle();
    expect(find.byType(OriginalScreen), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  StudyView view() => harness.container.read(studyViewProvider(rendition));

  List<String> hidden() =>
      harness.container
          .read(sharedPreferencesProvider)
          .getStringList(OriginalLayers.sourceKeyOf(rendition)) ??
      const [];

  testWidgets('el detalle muestra el original con lo marcado y, debajo, qué '
      'tiene marcado; las fichas van adentro', (tester) async {
    await saveSource(withSummary: true);
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));

    expect(find.byKey(const Key('original-study-bar')), findsNothing);
    expect(find.byKey(const Key('original-marks-line')), findsOneWidget);
    expect(find.byKey(const Key('original-marks-summary')), findsOneWidget);
    expect(find.byKey(const Key('original-marks-keyword')), findsNothing);
    // Se abre como lo dejó la persona: lo marcado, a la vista.
    expect(view(), markedCopyStudyView());
  });

  testWidgets('lo oculto, en el renglón, con el punto hueco: el lector de '
      'pantalla lo dice', (tester) async {
    await saveSource(withSummary: true);
    await harness.container
        .read(sourceOriginalHiddenProvider(rendition).notifier)
        .setHidden(StudyMarkKind.summary, hidden: true);
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));

    final line = find.byKey(const Key('original-marks-line'));
    expect(
      tester.getSemantics(line).label,
      es.f45S7bMarksSaid(es.f45S7bMarksHidden(es.studyLegendSummary)),
    );
    final dot = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('original-marks-summary')),
        matching: find.byType(Container),
      ),
    );
    expect((dot.decoration! as BoxDecoration).color, isNull);
  });

  testWidgets('sin nada marcado, el renglón dice dónde se marca', (
    tester,
  ) async {
    await saveSource();
    await pumpApp(tester, harness);
    await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));

    expect(find.text(es.f45S7bMarksNone), findsOneWidget);
  });

  testWidgets('a pantalla completa, el mismo original que en Procesado: las '
      'fichas arriba, sobre la fuente, y el lector con A− A+', (tester) async {
    await saveSource(withSummary: true);
    await openOriginal(tester);

    expect(find.byKey(const Key('original-study-panel')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('original-study-state-summary')))
          .data,
      es.f43OrigStateDone('summary'),
    );
    final reader = tester.widget<DocumentReaderView>(
      find.byType(DocumentReaderView),
    );
    expect(reader.study!.renditionId, rendition);
    expect(reader.showFontControls, isTrue);
  });

  testWidgets('ocultar lo marcado queda recordado para esa fuente, y no toca '
      'la copia de Procesado', (tester) async {
    await saveSource(withSummary: true);
    await openOriginal(tester);

    await tap(tester, 'original-study-summary');
    expect(view().summary, isFalse);
    expect(hidden(), [StudyMarkKind.summary.name]);
    expect(
      harness.container.read(
        studyViewProvider(processedOriginalStudyKeyFor('roma')),
      ),
      markedCopyStudyView(),
    );

    // Se vuelve a abrir como quedó.
    harness.container.invalidate(studyViewProvider(rendition));
    expect(view().summary, isFalse);

    await tap(tester, 'original-study-summary');
    expect(view().summary, isTrue);
    expect(hidden(), isEmpty);
  });

  testWidgets('el menú de una ficha no ofrece «Borrar las marcas»: de la '
      'Biblioteca nada se borra de una vez; sí retocar a mano y rehacer', (
    tester,
  ) async {
    await saveSource(withSummary: true);
    await openOriginal(tester);

    await tap(tester, 'original-study-more-summary');

    expect(find.byKey(const Key('original-study-menu-clear')), findsNothing);
    expect(
      find.byKey(const Key('original-study-menu-retouch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('original-study-menu-redoWithAi')),
      findsOneWidget,
    );
  });

  testWidgets('«Con IA» analiza el texto de la fuente, con su clave y su '
      'elemento', (tester) async {
    await saveSource();
    await openOriginal(tester);

    await tap(tester, 'original-study-synthesis');
    expect(
      find.byKey(const Key('original-study-choice-synthesis')),
      findsOneWidget,
    );
    await tap(tester, 'original-study-choice-ai');

    final analysis = analyses[rendition]!;
    expect(analysis.starts, hasLength(1));
    expect(analysis.starts.single.itemId, 'roma');
    expect(analysis.starts.single.content, text);
    expect(view().synthesis, isTrue);
  });

  testWidgets('mientras la IA analiza la fuente, cada ficha dice su avance '
      'y la franja ofrece «Parar»', (tester) async {
    await saveSource();
    await openOriginal(tester);

    analyses[rendition]!.shown = const StudyAnalysisRunning(
      StudyProgress(partsDone: 1, partsTotal: 4),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('original-study-state-summary')))
          .data,
      es.f45S4StateWorking(25),
    );
    expect(find.text(es.studyStop), findsOneWidget);
  });

  group('en un teléfono', () {
    for (final (name, theme) in [
      ('claro', AppThemeChoice.light),
      ('oscuro', AppThemeChoice.dark),
    ]) {
      testWidgets('a 360 dp con la letra al doble, tema $name: el original '
          'no desborda', (tester) async {
        await saveSource(withSummary: true);
        await harness.container
            .read(themeChoiceNotifierProvider.notifier)
            .setChoice(theme);
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        await pushAndSettle(tester, harness, RoutePaths.itemDetail('roma'));
        // El editor de propiedades del detalle se desborda con la letra de
        // las pruebas desde antes de F45 (`PropertyEditor`, en `main`): no es
        // del original, que es lo que se mira acá.
        tester.takeException();

        final open = find.byKey(const Key('embedded-viewer-read-as-book'));
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('original-study-panel')), findsOneWidget);
      });
    }
  });
}
