import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../support/fake_shared_content_listener.dart';
import '../../support/vault_test_doubles.dart';

/// El shell de navegación (barra abajo en celular, riel al costado en
/// escritorio) contra el router real: es la única forma de probarlo, porque
/// `StatefulNavigationShell` lo construye `go_router` en su propio
/// `builder`, no algo que se pueda instanciar a mano.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildRoutedApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(goRouterProvider),
        ),
      ),
    );
  }

  ProviderContainer buildUnlockedContainer() {
    final container = ProviderContainer(
      overrides: [
        vaultLocalDataSourceProvider.overrideWithValue(
          FakeVaultLocalDataSource.withPin('246810'),
        ),
        pinHasherProvider.overrideWithValue(FakePinHasher()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sharedContentListenerProvider.overrideWithValue(
          FakeSharedContentListener(),
        ),
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultSessionControllerProvider.notifier).markUnlocked();
    return container;
  }

  // `tester.view.physicalSize` + `devicePixelRatio = 1` fija el ancho lógico
  // exacto que ve `MediaQuery.sizeOf`: `setSurfaceSize` a secas no alcanza,
  // porque el `devicePixelRatio` por defecto de las pruebas no es 1.
  void setLogicalWidth(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('ancho angosto (celular)', () {
    testWidgets('usa una barra de navegación abajo, no un riel', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('tocar un destino cambia de pestaña', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('ancho amplio (escritorio)', () {
    testWidgets('usa un riel de navegación al costado, no una barra', (
      tester,
    ) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('justo en el punto de quiebre ya es el riel, no la barra', (
      tester,
    ) async {
      setLogicalWidth(tester, kNavRailBreakpoint);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });
}
