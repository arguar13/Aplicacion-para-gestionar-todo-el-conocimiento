import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/usecases/analyze_for_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_study_analysis.dart';

/// Cómo se ven los botones de estudio del original (F43, paso 15, M5): en
/// los nueve temas, con la letra al doble en 360 dp, en cada estado —sin
/// hacer, generándose, hecho y oculto—, y que lo que dicen se lea.
void main() {
  final es = AppLocalizationsEs();
  const documentId = 'doc';
  const text = 'Roma fundó colonias. Cartago perdió la guerra.';
  final originalKey = processedOriginalStudyKeyFor(documentId);
  const study = OriginalStudy(
    documentId: documentId,
    original: (
      itemId: documentId,
      renditionId: 'procesado-original:doc',
      content: text,
      markdown: false,
    ),
  );
  const marked = DocumentStudy(
    marks: [
      StudyMark(
        id: 'r',
        kind: StudyMarkKind.summary,
        origin: ContentOrigin.ai,
        start: 0,
        end: 20,
      ),
      StudyMark(
        id: 'k',
        kind: StudyMarkKind.keyword,
        origin: ContentOrigin.ai,
        start: 0,
        end: 4,
      ),
    ],
    analyzedUntil: text.length,
    complete: true,
  );

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final (hi, lo) = la > lb ? (la, lb) : (lb, la);
    return (hi + 0.05) / (lo + 0.05);
  }

  Future<FakeStudyAnalysis> pump(
    WidgetTester tester, {
    required ThemeData theme,
    Size size = const Size(800, 900),
    double textScale = 1,
    Set<String> hidden = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      if (hidden.isNotEmpty)
        'processed_original_hidden.$documentId': hidden.toList(),
    });
    final prefs = await SharedPreferences.getInstance();
    final analysis = FakeStudyAnalysis(renditionId: study.ownKey);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // Uno nuevo en cada prueba: con otros overrides, el de antes seguiría.
        key: UniqueKey(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          documentStudyProvider.overrideWith(
            (ref, id) => Stream.value(
              id == originalKey ? marked : DocumentStudy.notStarted,
            ),
          ),
          processedStudyTextProvider.overrideWith(
            (ref, id) async => right(null),
          ),
          studyAnalysisProvider.overrideWith((ref, id) => analysis),
        ],
        child: MaterialApp(
          theme: theme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: OriginalStudyBar(study: study),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return analysis;
  }

  Color labelColor(WidgetTester tester, StudyMarkKind kind, String label) =>
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('original-study-${kind.name}')),
              matching: find.text(label),
            ),
          )
          .style!
          .color!;

  final themes = {
    for (final choice in AppThemeChoice.values)
      for (final theme in choice.previews) theme,
  };

  testWidgets('en los nueve temas: hecho, lleno con su color y letra oscura; '
      'sin hacer, con la letra del tema; las dos se leen', (tester) async {
    expect(themes, hasLength(AppThemeChoice.values.length - 1));
    for (final theme in themes) {
      await pump(tester, theme: theme);
      expect(tester.takeException(), isNull);
      final palette = StudyPalette.of(theme.brightness);

      final done = labelColor(
        tester,
        StudyMarkKind.summary,
        es.studyLegendSummary,
      );
      expect(done, StudyPalette.ink);
      expect(
        contrast(Colors.black, palette.summary),
        greaterThanOrEqualTo(4.5),
      );
      final none = labelColor(
        tester,
        StudyMarkKind.synthesis,
        es.studyLegendSynthesis,
      );
      expect(none, theme.colorScheme.onSurface);
      expect(
        contrast(none, theme.colorScheme.surfaceContainerLow),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('en 360 dp con la letra al doble, cada estado entra sin '
      'desbordar: sin hacer, hecho, oculto y generándose', (tester) async {
    for (final theme in [themes.first, themes.last]) {
      final analysis = await pump(
        tester,
        theme: theme,
        size: const Size(360, 1400),
        textScale: 2,
        hidden: {StudyMarkKind.keyword.name},
      );
      expect(tester.takeException(), isNull);
      expect(find.text(es.f43OrigStateNone), findsOneWidget);
      expect(find.text(es.f43OrigStateDone('summary')), findsOneWidget);
      expect(find.text(es.f43OrigStateHidden('keyword')), findsOneWidget);

      analysis.shown = const StudyAnalysisRunning(
        StudyProgress(partsDone: 3, partsTotal: 4),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(es.f45S4StateWorking(75)), findsNWidgets(3));
      // La barra no gira: un valor siempre.
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('original-study-progress-keyword')),
            )
            .value,
        0.75,
      );
    }
  });

  group('una fila de tres fichas (F45, paso 4)', () {
    Rect chip(WidgetTester tester, StudyMarkKind kind) =>
        tester.getRect(find.byKey(Key('original-study-${kind.name}')));

    testWidgets('en una pantalla ancha, las tres en una fila, del mismo ancho '
        'y el mismo alto', (tester) async {
      await pump(tester, theme: themes.first);

      expect(find.byKey(const Key('original-study-chips-3')), findsOneWidget);
      final rects = [
        for (final kind in StudyMarkKind.values) chip(tester, kind),
      ];
      for (final rect in rects.skip(1)) {
        expect(rect.top, rects.first.top);
        expect(rect.height, rects.first.height);
        expect(rect.width, closeTo(rects.first.width, 0.5));
      }
    });

    testWidgets('en 360 dp con la letra al doble pasan a más renglones, sin '
        'desbordar ni cortar una palabra; las de un renglón, del mismo '
        'alto', (tester) async {
      for (final theme in [themes.first, themes.last]) {
        await pump(
          tester,
          theme: theme,
          size: const Size(360, 1400),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('original-study-chips-3')), findsNothing);
        final rects = [
          for (final kind in StudyMarkKind.values) chip(tester, kind),
        ];
        // Más de un renglón: la tercera ya no está al lado de la primera.
        expect(rects.last.top, greaterThan(rects.first.top));
        for (final a in rects) {
          for (final b in rects) {
            if (a.top == b.top) expect(a.height, b.height);
          }
        }
        // Ninguna palabra se corta: cada nombre entra en su renglón entero.
        for (final word in ['Palabras', 'clave', 'Resumen', 'Síntesis']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.textContaining(word).first,
          );
          final lines = paragraph
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: paragraph.text.toPlainText().indexOf(word),
                  extentOffset:
                      paragraph.text.toPlainText().indexOf(word) + word.length,
                ),
              )
              .map((box) => box.top)
              .toSet();
          expect(lines, hasLength(1), reason: word);
        }
      }
    });

    testWidgets('el punto de color es la leyenda: el color de cada '
        'resaltador, lleno a la vista y hueco si está oculto; no hay otra '
        'leyenda que repita los colores', (tester) async {
      await pump(
        tester,
        theme: themes.first,
        hidden: {StudyMarkKind.keyword.name},
      );
      final palette = StudyPalette.of(themes.first.brightness);

      BoxDecoration dot(StudyMarkKind kind) =>
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(Key('original-study-dot-${kind.name}')),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      // Sin hacer: el color del resaltador, lleno.
      expect(dot(StudyMarkKind.synthesis).color, palette.synthesis);
      // Oculto: hueco, con el borde de su color.
      expect(dot(StudyMarkKind.keyword).color, isNull);
      expect(
        (dot(StudyMarkKind.keyword).border! as Border).top.color,
        palette.keyword,
      );
      // Hecho y a la vista: la ficha es del color, y el punto, oscuro.
      expect(dot(StudyMarkKind.summary).color, StudyPalette.ink);
      expect(find.byKey(const Key('original-study-legend')), findsNothing);
      expect(find.text(es.studyLegendSummary), findsOneWidget);
    });

    testWidgets('el lector de pantalla dice nombre, marcas y estado, y qué '
        'hace tocarla', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        theme: themes.first,
        hidden: {StudyMarkKind.keyword.name},
      );

      SemanticsNode node(StudyMarkKind kind) =>
          tester.getSemantics(find.byKey(Key('original-study-${kind.name}')));

      expect(
        node(StudyMarkKind.synthesis),
        isSemantics(
          label: es.f43OrigButtonSemantics(
            es.studyLegendSynthesis,
            es.studySentenceCount(0),
            es.f43OrigStateNone,
          ),
          isButton: true,
          hasTapAction: true,
          onTapHint: es.f45S4ChipCreateHint,
          // Sin marcas no hay menú.
          hasLongPressAction: false,
        ),
      );
      expect(
        node(StudyMarkKind.summary),
        isSemantics(
          hasTapAction: true,
          onTapHint: es.f45S4ChipHideHint,
          hasLongPressAction: true,
          onLongPressHint: es.f43OrigMoreTooltip(es.studyLegendSummary),
        ),
      );
      expect(
        node(StudyMarkKind.keyword),
        isSemantics(
          onTapHint: es.f45S4ChipShowHint,
          onLongPressHint: es.f43OrigMoreTooltip(es.studyKeywords),
        ),
      );
      handle.dispose();
    });
  });

  test('cuántas fichas por renglón: todas si entran, la mitad si no, y una '
      'si tampoco', () {
    expect(studyChipsPerRow(width: 328, needed: 100, count: 3), 3);
    expect(studyChipsPerRow(width: 328, needed: 150, count: 3), 2);
    expect(studyChipsPerRow(width: 328, needed: 170, count: 3), 1);
    // Justo: tres de 104 con dos huecos de 8 son 328.
    expect(studyChipsPerRow(width: 328, needed: 104, count: 3), 3);
  });

  testWidgets('el resumen y la síntesis a la vista: la leyenda suma «Resumen '
      'y síntesis»; con uno oculto, no', (tester) async {
    await pump(tester, theme: themes.first);
    expect(find.text(es.f43OrigLegendBoth), findsOneWidget);

    await pump(
      tester,
      theme: themes.first,
      hidden: {StudyMarkKind.synthesis.name},
    );
    expect(find.text(es.f43OrigLegendBoth), findsNothing);
  });
}
