import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/features/viewer/presentation/screens/web_page_viewer_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/web_page_viewer_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';

/// La página archivada a pantalla completa (F36): con su artículo, arriba
/// van los botones de estudiar, como en el lector, y el artículo se ofrece
/// entero para escuchar.
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
          studyRepositoryProvider.overrideWithValue(
            MemoryStudyRepository(DocumentStudy.notStarted),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home:
              home ??
              WebPageViewerScreen(
                path: '/no/existe/pagina.html',
                title: 'Una nota',
                text: withText ? article : null,
              ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('con su artículo, arriba los botones de estudiar', (
    tester,
  ) async {
    await pump(tester, withText: true);

    expect(find.byType(StudyBar), findsOneWidget);
    expect(find.byKey(const Key('study-toggle-synthesis')), findsOneWidget);
  });

  testWidgets('sin artículo, no hay qué estudiar', (tester) async {
    await pump(tester, withText: false);

    expect(find.byType(StudyBar), findsNothing);
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
