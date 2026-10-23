import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study/presentation/widgets/study_toggles.dart';
import 'package:sinapsis/features/viewer/presentation/screens/web_page_viewer_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../support/memory_study_repository.dart';

/// La página archivada a pantalla completa (F36): con su artículo, arriba
/// van los botones de estudiar, como en el lector.
void main() {
  Future<void> pump(WidgetTester tester, {required bool withText}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studyRepositoryProvider.overrideWithValue(
            MemoryStudyRepository(DocumentStudy.notStarted),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WebPageViewerScreen(
            path: '/no/existe/pagina.html',
            title: 'Una nota',
            text: withText
                ? (
                    itemId: 'i1',
                    renditionId: 'r1',
                    content: 'El artículo.',
                    markdown: true,
                  )
                : null,
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
}
