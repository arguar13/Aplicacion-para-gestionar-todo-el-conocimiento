import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/transform/domain/documents/pdf_page_text.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/pdf_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_study_analysis.dart';
import '../../../../../support/memory_study_repository.dart';
import '../../../../../support/read_aloud_test_support.dart';

/// El original de un PDF a pantalla completa —el mismo en Procesado y en la
/// Biblioteca (F45, paso 7b)—, para escuchar dentro de él: ofrece su texto
/// extraído entero, con lo estudiado, y empieza por la página que se ve.
/// Arriba, las fichas donde se marca; sin texto, ninguna. Que lo que
/// suena se pinte sobre las letras y la vista lo siga se prueba en
/// `pdf_study_overlay_test.dart` y, con un PDF de verdad, en
/// `pdf_selection_real_test.dart`.
void main() {
  final es = AppLocalizationsEs();
  const content =
      'Primera página.$pdfPageSeparator'
      'Segunda página, con una oración.';
  const text = (
    itemId: 'i1',
    renditionId: 'r1',
    content: content,
    markdown: false,
  );

  late ProviderContainer container;
  late MemoryStudyRepository studies;

  setUp(() async {
    studies = MemoryStudyRepository(DocumentStudy.notStarted);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        studyRepositoryProvider.overrideWithValue(studies),
        studyAnalysisProvider.overrideWith((ref, id) => FakeStudyAnalysis()),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester, {bool withText = true}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OriginalScreen(
            title: 'Un PDF',
            body: OriginalView(
              format: OriginalFormat.pdf,
              path: '/no/existe/documento.pdf',
              title: 'Un PDF',
              text: withText ? text : null,
              study: withText ? const OriginalStudy.source(text) : null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  ReadableDocument? offered() => container.read(currentReadableProvider);

  testWidgets('ofrece su texto entero, con lo estudiado: el mismo documento '
      'que «Escuchar» de la tarjeta', (tester) async {
    final start = content.indexOf('Segunda');
    studies.set(
      DocumentStudy(
        marks: [
          StudyMark(
            id: 's1',
            kind: StudyMarkKind.summary,
            origin: ContentOrigin.ai,
            start: start,
            end: content.length,
          ),
        ],
        analyzedUntil: content.length,
        complete: true,
      ),
    );
    await pump(tester);

    final document = offered()!;
    expect(document.id, studyReadableId('r1'));
    expect(document.title, 'Un PDF');
    expect(document.segments, buildReadableSegments(content, sourceKey: 'r1'));
    expect(document.segmentsOf(ReadScope.summary).single.start, start);
    // El PDF todavía no se abrió: no se sabe qué página se ve.
    expect(document.startIndexOf(ReadScope.all), 0);
    expect(find.text(es.readAloudBackToReading), findsOneWidget);
    expect(find.byType(PdfViewerView), findsOneWidget);
  });

  testWidgets('con su texto, arriba las fichas donde se marca la fuente', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('original-study-panel')), findsOneWidget);
    expect(find.byKey(const Key('original-study-summary')), findsOneWidget);
  });

  testWidgets('sin su texto no hay nada que escuchar ni que marcar', (
    tester,
  ) async {
    await pump(tester, withText: false);

    expect(offered(), isNull);
    expect(find.byKey(const Key('original-study-panel')), findsNothing);
    expect(find.text(es.readAloudBackToReading), findsNothing);
  });
}
