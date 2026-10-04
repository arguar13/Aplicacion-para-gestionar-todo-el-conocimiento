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
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../support/fake_shared_content_listener.dart';
import '../../support/map_overrides.dart';
import '../../support/vault_test_doubles.dart';

/// El shell de navegación (barra abajo en celular, riel al costado en
/// escritorio) contra el router real: es la única forma de probarlo, porque
/// `StatefulNavigationShell` lo construye `go_router` en su propio
/// `builder`, no algo que se pueda instanciar a mano.
void main() {
  final es = AppLocalizationsEs();
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
        deviceBootProvider.overrideWithValue(testDeviceBoot),
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
        // La pestaña del Mapa calcula en un isolate: ver `mapInlineOverrides`.
        ...mapInlineOverrides,
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

      await tester.tap(find.byIcon(Icons.hub_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);
    });

    testWidgets('la barra muestra cinco destinos y un «Más» (F13, D1)', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      final labels = [
        for (final d in tester.widgetList<NavigationDestination>(
          find.byType(NavigationDestination),
        ))
          d.label,
      ];
      expect(labels, [
        es.navLibrary,
        es.navInbox,
        es.navAtlas,
        es.navMap,
        es.navReview,
        es.navMore,
      ]);
    });

    testWidgets('el Atlas es un destino de la barra', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AtlasScreen), findsOneWidget);
    });

    testWidgets(
      '«Más» abre una hoja con Explorador, Chat, Cuadernos y Ajustes',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();

        for (final label in [
          es.navExplorer,
          es.navChat,
          es.navNotebooks,
          es.navSettings,
        ]) {
          expect(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text(label),
            ),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('elegir un destino de «Más» lo abre, y «Más» queda marcado', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more-2')));
      await tester.pumpAndSettle();

      expect(find.byType(ExplorerScreen), findsOneWidget);
      // La hoja se cerró y la barra marca «Más», el último destino.
      expect(find.byType(BottomSheet), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, bar.destinations.length - 1);
    });

    testWidgets('Ajustes, Chat y Cuadernos también están detrás de «Más»', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more-6')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more-4')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more-8')));
      await tester.pumpAndSettle();
      expect(find.byType(NotebooksScreen), findsOneWidget);
    });

    testWidgets('un destino de la barra deja de marcar «Más»', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-more-6')));
      await tester.pumpAndSettle();

      // El ícono del destino, en la barra: la pantalla abierta puede mostrar
      // el mismo —Ajustes lo usa para el interruptor del Atlas (F27)—.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.account_tree_outlined),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      // El Atlas es el tercero de la barra.
      expect(bar.selectedIndex, 2);
    });

    testWidgets('la Bandeja de entrada es un destino más', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.move_to_inbox_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
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

    testWidgets('el riel muestra los nueve destinos, en su orden', (
      tester,
    ) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = [
        for (final d in rail.destinations) (d.label as Text).data,
      ];
      expect(labels, [
        es.navLibrary,
        es.navInbox,
        es.navAtlas,
        es.navExplorer,
        es.navMap,
        es.navChat,
        es.navNotebooks,
        es.navReview,
        es.navSettings,
      ]);
    });

    testWidgets('en el riel, tocar el Atlas lo abre y lo marca', (
      tester,
    ) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.account_tree_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AtlasScreen), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
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
