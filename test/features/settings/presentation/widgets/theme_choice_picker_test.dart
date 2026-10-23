import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/settings/presentation/widgets/theme_choice_picker.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final es = AppLocalizationsEs();

  /// Monta el selector dentro de una app que lee el tema elegido igual que la
  /// de verdad (`App`): así se ve lo que pasa en toda la app al elegir.
  Future<SharedPreferences> pumpPicker(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Consumer(
          builder: (context, ref, _) {
            final choice = ref.watch(themeChoiceNotifierProvider);
            return MaterialApp(
              theme: choice.theme,
              darkTheme: choice.darkTheme,
              themeMode: choice.mode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('es'),
              home: const Scaffold(
                body: SingleChildScrollView(child: ThemeChoicePicker()),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  ThemeData appTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(ThemeChoicePicker)));

  Finder swatch(AppThemeChoice choice) =>
      find.byKey(Key('theme-swatch-${choice.name}'));

  /// Cuál muestra tiene la marca de «elegido».
  List<String> checked(WidgetTester tester) => [
    for (final choice in AppThemeChoice.values)
      if (find
          .descendant(of: swatch(choice), matching: find.byIcon(Icons.check))
          .evaluate()
          .isNotEmpty)
        choice.name,
  ];

  testWidgets('hay una muestra por cada tema, con su nombre', (tester) async {
    await pumpPicker(tester);

    expect(find.text(es.themeModeTooltip), findsOneWidget);
    for (final choice in AppThemeChoice.values) {
      expect(swatch(choice), findsOneWidget, reason: choice.name);
    }
    for (final (choice, name) in [
      (AppThemeChoice.system, 'Sistema'),
      (AppThemeChoice.light, 'Claro'),
      (AppThemeChoice.dark, 'Oscuro'),
      (AppThemeChoice.sepia, 'Sepia'),
      (AppThemeChoice.night, 'Noche'),
      (AppThemeChoice.forest, 'Bosque'),
      (AppThemeChoice.ocean, 'Océano'),
      (AppThemeChoice.lavender, 'Lavanda'),
      (AppThemeChoice.graphite, 'Grafito'),
    ]) {
      expect(
        find.descendant(of: swatch(choice), matching: find.text(name)),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets('cada muestra se pinta con los colores de su tema, no con los '
      'del tema que está puesto', (tester) async {
    await pumpPicker(tester);

    for (final choice in AppThemeChoice.values) {
      final preview = find.byKey(Key('theme-swatch-preview-${choice.name}'));
      for (final theme in choice.previews) {
        // El fondo de la pantallita y su tarjeta.
        expect(
          find.descendant(
            of: preview,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is ColoredBox && w.color == theme.scaffoldBackgroundColor,
            ),
          ),
          findsOneWidget,
          reason: '${choice.name} fondo',
        );
        expect(
          find.descendant(
            of: preview,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  (w.decoration as BoxDecoration).color ==
                      theme.colorScheme.surface,
            ),
          ),
          findsOneWidget,
          reason: '${choice.name} tarjeta',
        );
        // Y los puntos de los dos acentos.
        for (final accent in [
          theme.colorScheme.primary,
          theme.colorScheme.secondary,
        ]) {
          expect(
            find.descendant(
              of: preview,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).color == accent &&
                    (w.decoration! as BoxDecoration).shape == BoxShape.circle,
              ),
            ),
            findsWidgets,
            reason: '${choice.name} acento',
          );
        }
      }
    }
    // El del sistema muestra los dos lados, el claro y el oscuro.
    expect(
      find.descendant(
        of: find.byKey(const Key('theme-swatch-preview-system')),
        matching: find.byType(ColoredBox),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('arranca en «Sistema», con la marca en esa muestra', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(checked(tester), ['system']);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text(es.themeModeSystem),
      ),
      findsOneWidget,
    );
  });

  testWidgets('elegir Sepia aplica el tema al instante en toda la app y lo '
      'guarda', (tester) async {
    final prefs = await pumpPicker(tester);
    expect(appTheme(tester).brightness, Brightness.light);

    await tester.tap(swatch(AppThemeChoice.sepia));
    await tester.pumpAndSettle();

    final theme = appTheme(tester);
    final sepia = AppThemeChoice.sepia.theme;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, sepia.scaffoldBackgroundColor);
    expect(theme.colorScheme.primary, sepia.colorScheme.primary);
    expect(checked(tester), ['sepia']);
    // El título de la fila muestra el nombre del elegido.
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('Sepia')),
      findsOneWidget,
    );
    expect(prefs.getString('app_theme_mode'), 'sepia');
  });

  testWidgets('un tema oscuro con nombre da el brillo oscuro y uno claro, '
      'el claro', (tester) async {
    await pumpPicker(tester);

    for (final (choice, brightness) in [
      (AppThemeChoice.night, Brightness.dark),
      (AppThemeChoice.lavender, Brightness.light),
      (AppThemeChoice.graphite, Brightness.dark),
      (AppThemeChoice.forest, Brightness.dark),
      (AppThemeChoice.sepia, Brightness.light),
      (AppThemeChoice.ocean, Brightness.dark),
    ]) {
      await tester.tap(swatch(choice));
      await tester.pumpAndSettle();

      expect(appTheme(tester).brightness, brightness, reason: choice.name);
      expect(
        appTheme(tester).scaffoldBackgroundColor,
        choice.palette!.background,
        reason: choice.name,
      );
      expect(checked(tester), [choice.name]);
    }
  });

  testWidgets('volver a «Claro» u «Oscuro» deja el tema de siempre', (
    tester,
  ) async {
    await pumpPicker(tester);
    await tester.tap(swatch(AppThemeChoice.night));
    await tester.pumpAndSettle();
    expect(appTheme(tester).scaffoldBackgroundColor, Colors.black);

    await tester.tap(swatch(AppThemeChoice.dark));
    await tester.pumpAndSettle();
    expect(appTheme(tester).brightness, Brightness.dark);
    expect(
      appTheme(tester).scaffoldBackgroundColor,
      AppThemeChoice.dark.darkTheme.scaffoldBackgroundColor,
    );

    await tester.tap(swatch(AppThemeChoice.light));
    await tester.pumpAndSettle();
    expect(appTheme(tester).brightness, Brightness.light);
    expect(
      appTheme(tester).scaffoldBackgroundColor,
      AppThemeChoice.light.theme.scaffoldBackgroundColor,
    );
  });

  testWidgets('lo que guardaba la versión anterior abre con ese tema '
      'elegido', (tester) async {
    await pumpPicker(tester, stored: {'app_theme_mode': 'dark'});

    expect(checked(tester), ['dark']);
    expect(appTheme(tester).brightness, Brightness.dark);
  });

  testWidgets('un tema con nombre guardado abre elegido', (tester) async {
    await pumpPicker(tester, stored: {'app_theme_mode': 'ocean'});

    expect(checked(tester), ['ocean']);
    expect(
      appTheme(tester).scaffoldBackgroundColor,
      AppThemeChoice.ocean.palette!.background,
    );
  });

  testWidgets('cada muestra dice su nombre y si está elegida a quien lee la '
      'pantalla', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPicker(tester);

    expect(
      tester.getSemantics(swatch(AppThemeChoice.system)),
      isSemantics(
        label: 'Sistema',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(swatch(AppThemeChoice.sepia)),
      isSemantics(
        label: 'Sepia',
        isButton: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('las muestras son lo bastante grandes para tocarlas', (
    tester,
  ) async {
    await pumpPicker(tester);

    for (final choice in AppThemeChoice.values) {
      final size = tester.getSize(swatch(choice));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });
}
