import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/features/vault/presentation/screens/unlock_vault_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../support/fake_shared_content_listener.dart';
import '../../support/vault_test_doubles.dart';

/// El destino más probable de romperse en silencio al mover biblioteca,
/// grafo, chat y repaso a un `StatefulShellRoute`: que el guard de la
/// bóveda deje de aplicarse dentro de una rama del shell.
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

  /// Arranca con una bóveda que existe pero está bloqueada — a diferencia de
  /// `buildUnlockedContainer()` en otros tests de router, acá nunca se llama
  /// a `markUnlocked()`.
  ProviderContainer buildLockedContainer() {
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
    return container;
  }

  for (final path in [
    RoutePaths.inbox,
    RoutePaths.graph,
    RoutePaths.review,
    RoutePaths.chat,
  ]) {
    testWidgets('con la bóveda bloqueada, ir directo a $path igual redirige al '
        'desbloqueo', (tester) async {
      final container = buildLockedContainer();

      await tester.pumpWidget(buildRoutedApp(container));
      await tester.pumpAndSettle();
      expect(find.byType(UnlockVaultScreen), findsOneWidget);

      container.read(goRouterProvider).go(path);
      await tester.pumpAndSettle();

      expect(find.byType(UnlockVaultScreen), findsOneWidget);
    });
  }
}
