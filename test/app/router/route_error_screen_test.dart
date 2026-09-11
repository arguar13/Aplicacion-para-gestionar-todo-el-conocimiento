import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_error_screen.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../support/vault_test_doubles.dart';

void main() {
  late SharedPreferences prefs;

  final en = AppLocalizationsEn();
  final es = AppLocalizationsEs();

  final tUri = Uri.parse('/ruta-que-no-existe');

  setUp(() async {
    // Mismo contrato que cumplen los entry points de flavor y
    // `widget_test.dart`: `goRouterProvider` lee `EnvConfig.current` (para
    // decidir `debugLogDiagnostics`), y sin inicializar salta el assert que
    // exige haber elegido un flavor antes de construir la app.
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildIsolatedScreen({Locale locale = const Locale('es')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteErrorScreen(uri: tUri),
    );
  }

  group('contenido', () {
    testWidgets('muestra título, explicación y la dirección que falló', (
      tester,
    ) async {
      await tester.pumpWidget(buildIsolatedScreen());

      expect(find.text(es.routeNotFoundTitle), findsOneWidget);
      expect(find.text(es.routeNotFoundMessage), findsOneWidget);
      expect(find.text(tUri.toString()), findsOneWidget);
    });

    testWidgets('la dirección es seleccionable, para poder copiarla al '
        'reportar el problema', (tester) async {
      await tester.pumpWidget(buildIsolatedScreen());

      final address = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(address.data, tUri.toString());
    });

    testWidgets('el texto está traducido: en inglés no queda ni una cadena '
        'en español', (tester) async {
      await tester.pumpWidget(buildIsolatedScreen(locale: const Locale('en')));

      expect(find.text(en.routeNotFoundTitle), findsOneWidget);
      expect(find.text(en.routeNotFoundMessage), findsOneWidget);
      expect(find.text(en.routeNotFoundAction), findsOneWidget);
      // La regresión concreta que motivó esta pantalla: el mensaje estaba
      // escrito a mano en español dentro de `app_router.dart`, así que
      // salía igual con la app en inglés.
      expect(find.text(es.routeNotFoundTitle), findsNothing);
    });
  });

  group('integración con el router real', () {
    /// Monta el `GoRouter` de la app —no uno de mentira— para probar que el
    /// `errorBuilder` está efectivamente cableado a esta pantalla.
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

    /// Arranca con la bóveda ya abierta.
    ///
    /// Hace falta: el `redirect` global corre antes que el matching de
    /// rutas, así que con la bóveda cerrada NINGUNA dirección llega al
    /// `errorBuilder` — el guard las manda todas al desbloqueo primero. Es
    /// el comportamiento correcto (a alguien que no abrió la bóveda no se le
    /// confirma qué rutas existen), pero implica que esta pantalla solo es
    /// alcanzable con la bóveda abierta.
    ProviderContainer buildUnlockedContainer() {
      final container = ProviderContainer(
        overrides: [
          vaultLocalDataSourceProvider.overrideWithValue(
            FakeVaultLocalDataSource.withPin('246810'),
          ),
          pinHasherProvider.overrideWithValue(FakePinHasher()),
          sharedPreferencesProvider.overrideWithValue(prefs),
          // La biblioteca lee de la base en cuanto se monta; en un test va
          // en memoria, que además la deja vacía en cada caso.
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

    testWidgets('una URL que no corresponde a ninguna ruta cae en '
        'RouteErrorScreen', (tester) async {
      // Arrange
      final container = buildUnlockedContainer();

      await tester.pumpWidget(buildRoutedApp(container));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      // Act
      container.read(goRouterProvider).go(tUri.toString());
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(RouteErrorScreen), findsOneWidget);
      expect(find.text(es.routeNotFoundTitle), findsOneWidget);
    });

    testWidgets('el botón devuelve a un destino válido en vez de dejar al '
        'usuario encerrado', (tester) async {
      // Arrange
      final container = buildUnlockedContainer();

      await tester.pumpWidget(buildRoutedApp(container));
      await tester.pumpAndSettle();

      container.read(goRouterProvider).go(tUri.toString());
      await tester.pumpAndSettle();
      expect(find.byType(RouteErrorScreen), findsOneWidget);

      // Act
      await tester.tap(find.text(es.routeNotFoundAction));
      await tester.pumpAndSettle();

      // Assert: el botón va al splash y es el route guard el que elige el
      // destino final — por eso esta pantalla no necesita saber nada del
      // estado de la bóveda. Con la bóveda abierta, eso termina en el
      // dashboard.
      expect(find.byType(RouteErrorScreen), findsNothing);
      expect(find.byType(LibraryScreen), findsOneWidget);
    });
  });
}
