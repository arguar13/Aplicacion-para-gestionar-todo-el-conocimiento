import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_actions.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_view.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/mobile_page_width.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../../support/fake_study_analysis.dart';
import '../../../../../support/memory_study_repository.dart';
import '../../../../../support/read_aloud_test_support.dart';

/// El original de una página archivada a pantalla completa —el mismo en
/// Procesado y en la Biblioteca (F45, paso 7b)—: con su artículo, arriba van
/// las fichas donde se marca, y el artículo se ofrece entero para escuchar.
/// Se ve como en el navegador del teléfono, también en la computadora.
void main() {
  const article = (
    itemId: 'i1',
    renditionId: 'r1',
    content: 'El artículo.\nSu segunda línea.',
    markdown: true,
  );

  Future<void> pump(
    WidgetTester tester, {
    required bool withText,
    Widget? home,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          studyRepositoryProvider.overrideWithValue(
            MemoryStudyRepository(DocumentStudy.notStarted),
          ),
          studyAnalysisProvider.overrideWith((ref, id) => FakeStudyAnalysis()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home:
              home ??
              OriginalScreen(
                title: 'Una nota',
                body: OriginalView(
                  format: OriginalFormat.page,
                  path: '/no/existe/pagina.html',
                  title: 'Una nota',
                  text: withText ? article : null,
                  study: withText ? const OriginalStudy.source(article) : null,
                ),
              ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('con su artículo, arriba las fichas donde se marca; la página, '
      'como en el teléfono', (tester) async {
    await pump(tester, withText: true);

    expect(find.byKey(const Key('original-study-panel')), findsOneWidget);
    expect(find.byKey(const Key('original-study-synthesis')), findsOneWidget);
    expect(find.byType(MobilePageWidth), findsOneWidget);
    expect(
      tester.widget<WebPageViewerView>(find.byType(WebPageViewerView)).mobile,
      isTrue,
    );
  });

  testWidgets('sin artículo, no hay qué marcar', (tester) async {
    await pump(tester, withText: false);

    expect(find.byKey(const Key('original-study-panel')), findsNothing);
  });

  group('escuchar dentro de la página', () {
    ReadableDocument? offered(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(WebPageViewerView)),
    ).read(currentReadableProvider);

    testWidgets('ofrece el artículo entero: el mismo documento que «Escuchar» '
        'de la tarjeta de estudiar', (tester) async {
      await pump(tester, withText: true);
      await tester.pump();

      final document = offered(tester)!;
      expect(document.id, studyReadableId('r1'));
      expect(document.title, 'Una nota');
      expect(
        document.segments,
        buildReadableSegments(article.content, sourceKey: 'r1', markdown: true),
      );
      // Con «Leer: Todo · Resumen · Síntesis · Palabras clave», apagadas las
      // partes que todavía no tienen nada.
      expect(document.hasScopes, isTrue);
      expect(document.offers(ReadScope.summary), isFalse);
      expect(
        find.text(AppLocalizationsEs().readAloudBackToReading),
        findsOneWidget,
      );
    });

    testWidgets('embebida en el detalle solo pinta: lo que se escucha ahí lo '
        'ofrece el detalle', (tester) async {
      await pump(
        tester,
        withText: true,
        home: const Scaffold(
          body: WebPageViewerView(
            path: '/no/existe/pagina.html',
            text: article,
          ),
        ),
      );
      await tester.pump();

      expect(offered(tester), isNull);
      expect(
        find.text(AppLocalizationsEs().readAloudBackToReading),
        findsNothing,
      );
    });

    testWidgets('sin artículo no hay nada que escuchar', (tester) async {
      await pump(tester, withText: false);
      await tester.pump();

      expect(offered(tester), isNull);
    });
  });
}
