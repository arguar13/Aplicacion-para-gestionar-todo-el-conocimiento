import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  Future<void> pumpReader(WidgetTester tester, String content) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DocumentReaderScreen(title: 'Un libro', content: content),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('un documento corto no muestra controles de página', (
    tester,
  ) async {
    await pumpReader(tester, 'Todo el contenido entra en una sola página.');

    expect(
      find.text('Todo el contenido entra en una sola página.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets(
    'un documento largo se abre en la primera página, con el indicador y '
    'los controles',
    (tester) async {
      final pages = List.generate(5, (i) => 'Página número $i.');
      await pumpReader(tester, pages.join('\n\n---\n\n'));

      expect(find.text('Página número 0.'), findsOneWidget);
      expect(find.text(es.documentReaderPageOf(1, 5)), findsOneWidget);
    },
  );

  testWidgets('tocar "siguiente" avanza una página', (tester) async {
    final pages = List.generate(3, (i) => 'Página número $i.');
    await pumpReader(tester, pages.join('\n\n---\n\n'));

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('Página número 1.'), findsOneWidget);
    expect(find.text('Página número 0.'), findsNothing);
    expect(find.text(es.documentReaderPageOf(2, 3)), findsOneWidget);
  });

  testWidgets(
    'en la primera página "anterior" está deshabilitado, y en la última '
    '"siguiente" también',
    (tester) async {
      final pages = List.generate(2, (i) => 'Página número $i.');
      await pumpReader(tester, pages.join('\n\n---\n\n'));

      IconButton buttonWithIcon(IconData icon) => tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
      );

      expect(buttonWithIcon(Icons.chevron_left).onPressed, isNull);
      expect(buttonWithIcon(Icons.chevron_right).onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(buttonWithIcon(Icons.chevron_left).onPressed, isNotNull);
      expect(buttonWithIcon(Icons.chevron_right).onPressed, isNull);
    },
  );
}
