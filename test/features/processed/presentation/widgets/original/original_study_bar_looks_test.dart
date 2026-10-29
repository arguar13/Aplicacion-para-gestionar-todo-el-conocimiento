import 'package:flutter/material.dart';
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
      expect(find.text(es.f43OrigStateGenerating(75)), findsNWidgets(3));
    }
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
