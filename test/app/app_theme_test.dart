import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/create_vault_screen.dart';

import '../support/fake_shared_content_listener.dart';
import '../support/vault_test_doubles.dart';

/// El tema elegido (F39, decisión E) llega a la `App` de verdad: lo que está
/// guardado se aplica al abrir, y cambiarlo cambia toda la app al instante.
void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
  }) async {
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({'app_locale': 'es', ...stored});
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultLocalDataSourceProvider.overrideWithValue(
            FakeVaultLocalDataSource(),
          ),
          deviceBootProvider.overrideWithValue(testDeviceBoot),
          pinHasherProvider.overrideWithValue(FakePinHasher()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          sharedContentListenerProvider.overrideWithValue(
            FakeSharedContentListener(),
          ),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(App)));
  }

  MaterialApp materialApp(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp));

  ThemeData shownTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(CreateVaultScreen)));

  testWidgets('sin nada guardado, la app sigue al sistema con el claro y el '
      'oscuro de siempre', (tester) async {
    await pumpApp(tester);

    final app = materialApp(tester);
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('un tema con nombre guardado se aplica al abrir', (tester) async {
    await pumpApp(tester, stored: {'app_theme_mode': 'sepia'});

    final app = materialApp(tester);
    expect(app.themeMode, ThemeMode.light);
    expect(shownTheme(tester).brightness, Brightness.light);
    expect(
      shownTheme(tester).scaffoldBackgroundColor,
      AppThemeChoice.sepia.palette!.background,
    );
  });

  testWidgets('lo que guardaba la versión anterior se aplica igual', (
    tester,
  ) async {
    await pumpApp(tester, stored: {'app_theme_mode': 'dark'});

    expect(materialApp(tester).themeMode, ThemeMode.dark);
    expect(shownTheme(tester).brightness, Brightness.dark);
  });

  testWidgets('cambiar el tema cambia toda la app al instante', (tester) async {
    final container = await pumpApp(tester);

    await container
        .read(themeChoiceNotifierProvider.notifier)
        .setChoice(AppThemeChoice.night);
    await tester.pumpAndSettle();

    expect(materialApp(tester).themeMode, ThemeMode.dark);
    expect(shownTheme(tester).brightness, Brightness.dark);
    expect(shownTheme(tester).scaffoldBackgroundColor, Colors.black);

    await container
        .read(themeChoiceNotifierProvider.notifier)
        .setChoice(AppThemeChoice.lavender);
    await tester.pumpAndSettle();

    expect(materialApp(tester).themeMode, ThemeMode.light);
    expect(shownTheme(tester).brightness, Brightness.light);
    expect(
      shownTheme(tester).scaffoldBackgroundColor,
      AppThemeChoice.lavender.palette!.background,
    );
  });
}
