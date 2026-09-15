import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/viewer/presentation/providers/reader_font_scale_notifier.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  Future<void> pumpReader(WidgetTester tester, String content) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentReaderScreen(title: 'Un libro', content: content),
        ),
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

  group('tamaño de letra', () {
    testWidgets('agrandar la letra hace más grande el texto de la página', (
      tester,
    ) async {
      await pumpReader(tester, 'Un párrafo cualquiera.');

      EditableText textWidget() =>
          tester.widget<EditableText>(find.text('Un párrafo cualquiera.'));
      final before = textWidget().style.fontSize!;

      await tester.tap(find.byIcon(Icons.text_increase));
      await tester.pumpAndSettle();

      expect(textWidget().style.fontSize, greaterThan(before));
    });

    testWidgets('achicar la letra hace más chico el texto, hasta un piso', (
      tester,
    ) async {
      await pumpReader(tester, 'Un párrafo cualquiera.');

      EditableText textWidget() =>
          tester.widget<EditableText>(find.text('Un párrafo cualquiera.'));

      final steps = ((1 - ReaderFontScaleNotifier.min) / 0.1).round() + 2;
      for (var i = 0; i < steps; i++) {
        await tester.tap(find.byIcon(Icons.text_decrease));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final decreaseButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.text_decrease),
          matching: find.byType(IconButton),
        ),
      );
      expect(decreaseButton.onPressed, isNull);
      expect(
        textWidget().style.fontSize,
        moreOrLessEquals(
          (Theme.of(
                    tester.element(find.byType(DocumentReaderScreen)),
                  ).textTheme.bodyLarge?.fontSize ??
                  16) *
              ReaderFontScaleNotifier.min,
          epsilon: 0.5,
        ),
      );
    });
  });

  group('ir a página', () {
    testWidgets('tocar el indicador abre el selector de página', (
      tester,
    ) async {
      final pages = List.generate(10, (i) => 'Página número $i.');
      await pumpReader(tester, pages.join('\n\n---\n\n'));

      await tester.tap(find.text(es.documentReaderPageOf(1, 10)));
      await tester.pumpAndSettle();

      expect(find.text(es.documentReaderGoToPage), findsWidgets);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('elegir una página en el selector salta ahí', (tester) async {
      final pages = List.generate(10, (i) => 'Página número $i.');
      await pumpReader(tester, pages.join('\n\n---\n\n'));

      await tester.tap(find.text(es.documentReaderPageOf(1, 10)));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.documentReaderGoToPage).last);
      await tester.pumpAndSettle();

      expect(find.text('Página número 0.'), findsNothing);
    });

    testWidgets('cancelar el selector no cambia de página', (tester) async {
      final pages = List.generate(10, (i) => 'Página número $i.');
      await pumpReader(tester, pages.join('\n\n---\n\n'));

      await tester.tap(find.text(es.documentReaderPageOf(1, 10)));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text('Página número 0.'), findsOneWidget);
    });
  });
}
