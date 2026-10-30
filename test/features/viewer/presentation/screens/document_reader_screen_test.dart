import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  Future<void> pumpReader(
    WidgetTester tester,
    String content, {
    AppThemeChoice? theme,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: theme?.theme,
          darkTheme: theme?.darkTheme,
          themeMode: theme?.mode ?? ThemeMode.system,
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

  group('sigue el tema elegido (F39), en el modo «Sistema» del marco de '
      'lectura (F47, paso 1)', () {
    /// El fondo de lo que se lee y el color de la letra.
    (Color?, Color?) looks(WidgetTester tester) {
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      return (
        tester
            .widget<Scaffold>(find.byKey(const Key('reading-frame')))
            .backgroundColor,
        text.textSpan!.style?.color,
      );
    }

    for (final choice in [
      AppThemeChoice.sepia,
      AppThemeChoice.night,
      AppThemeChoice.lavender,
      AppThemeChoice.graphite,
    ]) {
      testWidgets('con ${choice.name}, el fondo y la letra son los del tema, '
          'sin la tarjeta de papel', (tester) async {
        await pumpReader(tester, 'Un texto para leer.', theme: choice);

        final scheme = choice.theme.colorScheme;
        expect(looks(tester), (scheme.surface, scheme.onSurface));
        expect(
          find.ancestor(
            of: find.byType(SelectableText),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).boxShadow != null,
            ),
          ),
          findsNothing,
        );
      });
    }
  });

  group('el tamaño de la letra, en Apariencia (F47, paso 1)', () {
    Future<void> slideTo(WidgetTester tester, {required bool max}) async {
      await tester.tap(find.byKey(const Key('reading-frame-appearance')));
      await tester.pumpAndSettle();
      final slider = find.byKey(const Key('reading-size'));
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      await tester.tapAt(
        max
            ? rect.centerRight - const Offset(4, 0)
            : rect.centerLeft + const Offset(4, 0),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }

    EditableText textWidget(WidgetTester tester) =>
        tester.widget<EditableText>(find.text('Un párrafo cualquiera.'));

    testWidgets('agrandar la letra hace más grande el texto de la página', (
      tester,
    ) async {
      await pumpReader(tester, 'Un párrafo cualquiera.');
      final before = textWidget(tester).style.fontSize!;

      await slideTo(tester, max: true);

      expect(textWidget(tester).style.fontSize, closeTo(before * 1.6, 0.01));
    });

    testWidgets('achicar la letra hace más chico el texto, hasta un piso', (
      tester,
    ) async {
      await pumpReader(tester, 'Un párrafo cualquiera.');
      final before = textWidget(tester).style.fontSize!;

      await slideTo(tester, max: false);

      expect(
        textWidget(tester).style.fontSize,
        closeTo(before * ReadingAppearanceNotifier.minScale, 0.01),
      );
    });
  });

  testWidgets('«Contenido» lleva los capítulos del libro, cada uno con su '
      'página, y tocar uno salta ahí (F47, paso 1)', (tester) async {
    final pages = [
      for (var i = 0; i < 6; i++) '# Capítulo $i\n\nTexto del capítulo $i.',
    ];
    await pumpReader(tester, pages.join('\n\n---\n\n'));

    await tester.tap(find.byKey(const Key('reading-frame-contents')));
    await tester.pumpAndSettle();
    expect(find.text('Capítulo 4'), findsOneWidget);
    expect(find.text(es.documentReaderPageOf(5, 6)), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-outline-4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reading-contents-sheet')), findsNothing);
    expect(find.text(es.documentReaderPageOf(5, 6)), findsOneWidget);
    expect(find.textContaining('Texto del capítulo 4.'), findsOneWidget);
  });

  testWidgets('dentro de una página se lee de corrido: la física de la '
      'plataforma, sin el impulso de pasar hojas (F45, mejora 13)', (
    tester,
  ) async {
    await pumpReader(tester, 'Un párrafo cualquiera.');
    final page = tester.widget<SingleChildScrollView>(
      find.ancestor(
        of: find.byType(SelectableText),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(page.physics, isNull);
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
