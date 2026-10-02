import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/read_aloud_test_support.dart';

/// El lector de libros con el lector flotante (F25): ofrece la página que
/// se ve y las que siguen, resalta lo que se lee y da vuelta la página
/// cuando el lector pasa a la siguiente.
void main() {
  final es = AppLocalizationsEs();
  late ProviderContainer container;

  final book = [
    for (var i = 0; i < 3; i++) 'Página número $i.',
  ].join('\n\n---\n\n');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpReader(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentReaderScreen(title: 'Un libro', content: book),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReadableDocument? offered() => container.read(currentReadableProvider);

  /// Saca al lector de la pantalla y deja que retire lo que ofrecía: lo
  /// retira después del cuadro en que se desmonta, y la prueba no termina
  /// con eso pendiente.
  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeReadAloudController reader() =>
      container.read(readAloudControllerProvider.notifier)
          as FakeReadAloudController;

  testWidgets('ofrece la página que se ve y las que siguen, cada línea con '
      'su página y su lugar en ella', (tester) async {
    await pumpReader(tester);

    final document = offered()!;
    expect(document.title, 'Un libro');
    expect(document.id, endsWith(':from:0'));
    final book = document.id.substring(
      0,
      document.id.length - ':from:0'.length,
    );
    expect(document.segments, [
      for (var i = 0; i < 3; i++)
        ReadableSegment(
          sourceKey: '$book:page:$i',
          start: 0,
          end: 16,
          spoken: 'Página número $i.',
        ),
    ]);

    await closeReader(tester);
  });

  testWidgets('lo que se lee se ve en amarillo, y cuando el lector pasa a la '
      'página siguiente, la da vuelta', (tester) async {
    await pumpReader(tester);
    final document = offered()!;

    reader().readAt(document, 0);
    await tester.pumpAndSettle();
    expect(readAloudHighlights(tester), ['Página número 0.']);

    reader().readAt(document, 1);
    await tester.pumpAndSettle();
    expect(find.text(es.documentReaderPageOf(2, 3)), findsOneWidget);
    expect(readAloudHighlights(tester), ['Página número 1.']);
    // Lo que se ofrece ahora empieza en la página que se ve.
    expect(offered()!.id, endsWith(':from:1'));
    expect(offered()!.segments.first.spoken, 'Página número 1.');

    await closeReader(tester);
  });

  testWidgets('pasar de página a mano ofrece desde esa página; sin la '
      'pantalla, nada', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(offered()!.segments.map((s) => s.spoken), [
      'Página número 1.',
      'Página número 2.',
    ]);

    await closeReader(tester);
    expect(offered(), isNull);
  });
}
