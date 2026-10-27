import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/viewer/domain/services/reader_pagination.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/document_first_page_preview.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';
import '../../../../support/time_growth.dart';

/// Un libro de millones de caracteres no puede trabar la interfaz al mostrar
/// su primera hoja ni al abrir el lector: la app dejaba de responder.
void main() {
  final es = AppLocalizationsEs();

  /// Un libro de [chapters] capítulos de unos 40 000 caracteres cada uno.
  String book(int chapters) => List.generate(
    chapters,
    (chapter) => [
      '## Capítulo $chapter',
      for (var p = 0; p < 50; p++)
        'La revolución industrial cambió el mundo de forma profunda y '
                'duradera para todos los pueblos del párrafo $chapter-$p, '
                'según cuentan los historiadores que la estudiaron. ' *
            5,
    ].join('\n\n'),
  ).join('\n\n---\n\n');

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
        studyRepositoryProvider.overrideWithValue(
          MemoryStudyRepository(DocumentStudy.notStarted),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget app(ProviderContainer container, Widget home) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  group('el lector de un libro largo', () {
    testWidgets('parte el libro en otro hilo: mientras tanto un indicador, y '
        'después las mismas páginas de siempre', (tester) async {
      final content = book(4);
      expect(content.length, greaterThan(kReaderInlineChars));
      final pages = readerPageRanges(content);

      await tester.pumpWidget(
        app(
          await container(),
          DocumentReaderScreen(title: 'Un libro', content: content),
        ),
      );
      await tester.pump();

      // Nada de la primera página todavía: el libro se está partiendo.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Capítulo 0'), findsNothing);

      for (var i = 0; i < 200; i++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Capítulo 0'), findsOneWidget);
      expect(
        find.text(es.documentReaderPageOf(1, pages.length)),
        findsOneWidget,
      );
    });

    testWidgets('un libro corto se ve de entrada, sin indicador', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          await container(),
          const DocumentReaderScreen(
            title: 'Un libro',
            content: 'Una página.\n\n---\n\nOtra página.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Una página.'), findsOneWidget);
      expect(find.text(es.documentReaderPageOf(1, 2)), findsOneWidget);
    });
  });

  group('la vista previa de un libro largo', () {
    Future<int> pumpPreview(WidgetTester tester, String content) async {
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        app(
          await container(),
          Scaffold(
            body: SizedBox(
              height: 500,
              child: DocumentFirstPagePreview(content: content, onTap: null),
            ),
          ),
        ),
      );
      final micros = watch.elapsedMicroseconds;
      expect(find.textContaining('Capítulo 0'), findsOneWidget);
      // Se saca de la pantalla para que la vuelta siguiente arme todo de nuevo.
      await tester.pumpWidget(const SizedBox());
      return micros;
    }

    testWidgets('muestra la primera hoja y el tiempo no crece con el libro: '
        'cuatro veces más texto, el mismo tiempo (no cuatro veces)', (
      tester,
    ) async {
      final small = book(15);
      final big = book(60);
      expect(big.length, greaterThan(small.length * 3.5));

      final growth = await timeGrowth(
        () => pumpPreview(tester, small),
        () => pumpPreview(tester, big),
      );

      expect(growth, lessThan(2.2));
    });
  });
}
