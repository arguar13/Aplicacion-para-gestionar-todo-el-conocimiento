import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart';
import 'package:sinapsis/app/navigation/nav_destinations.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_entry_screen.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/timeline/presentation/screens/timeline_screen.dart';
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
  // Las ramas por nombre: su número es su lugar en el árbol de rutas.
  final inbox = ShellBranch.inbox.index;
  final timeline = ShellBranch.timeline.index;
  final atlas = ShellBranch.atlas.index;
  final graph = ShellBranch.graph.index;
  final notebooks = ShellBranch.notebooks.index;
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

    testWidgets(
      'la barra son los cinco pasos en orden de uso, con Ajustes a la '
      'derecha y sin «Más» (F34)',
      (tester) async {
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
          es.navStepOrganize,
          es.navChat,
          es.navReview,
          es.navSettings,
        ]);
        expect(find.byIcon(Icons.more_horiz), findsNothing);
      },
    );

    // Cada destino de un paso con lista: su rama, la pantalla que abre y la
    // posición del paso en la barra.
    final listed = [
      (step: 'organize', branch: inbox, screen: InboxScreen, barIndex: 1),
      (step: 'organize', branch: timeline, screen: TimelineScreen, barIndex: 1),
      (step: 'organize', branch: atlas, screen: AtlasScreen, barIndex: 1),
      (step: 'organize', branch: graph, screen: MapScreen, barIndex: 1),
      (
        step: 'organize',
        branch: notebooks,
        screen: NotebooksScreen,
        barIndex: 1,
      ),
    ];

    testWidgets(
      '«Organizar» abre su lista: Bandeja, Línea de tiempo, Atlas, Mapa y '
      'Cuadernos, en ese orden y con para qué sirve cada uno —el Explorador '
      'ya no está (F36)—',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-step-organize')));
        await tester.pumpAndSettle();

        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text(es.navStepOrganize)),
          findsOneWidget,
        );
        final tiles = tester
            .widgetList<ListTile>(
              find.descendant(of: sheet, matching: find.byType(ListTile)),
            )
            .toList();
        expect(
          [for (final t in tiles) (t.key! as ValueKey<String>).value],
          [
            for (final branch in [inbox, timeline, atlas, graph, notebooks])
              'nav-step-item-$branch',
          ],
        );
        for (final hint in [
          es.navInboxHint,
          es.navTimelineHint,
          es.navAtlasHint,
          es.navMapHint,
          es.navNotebooksHint,
        ]) {
          expect(
            find.descendant(of: sheet, matching: find.text(hint)),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      '«Preguntar» abre el chat directo, sin lista, y queda marcado',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-step-ask')));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(ChatScreen), findsOneWidget);
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.selectedIndex, 2);
      },
    );

    for (final d in listed) {
      testWidgets(
        'elegir la rama ${d.branch} de «${d.step}» abre ${d.screen}, cierra '
        'la lista y marca el paso',
        (tester) async {
          setLogicalWidth(tester, 400);

          await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('nav-step-${d.step}')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('nav-step-item-${d.branch}')));
          await tester.pumpAndSettle();

          expect(find.byType(d.screen), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(bar.selectedIndex, d.barIndex);
        },
      );
    }

    testWidgets(
      'Biblioteca, Repasar y Ajustes abren directo, sin lista, y quedan '
      'marcados',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();

        for (final (step, screen, barIndex) in [
          ('review', ReviewEntryScreen, 3),
          ('settings', SettingsScreen, 4),
          ('save', LibraryScreen, 0),
        ]) {
          await tester.tap(find.byKey(ValueKey('nav-step-$step')));
          await tester.pumpAndSettle();

          expect(find.byType(BottomSheet), findsNothing, reason: step);
          expect(find.byType(screen), findsOneWidget, reason: step);
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(bar.selectedIndex, barIndex, reason: step);
        }
      },
    );

    testWidgets('la lista marca el destino que está abierto, y solo ese', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-step-organize')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('nav-step-item-$atlas')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-step-organize')));
      await tester.pumpAndSettle();

      final selected = {
        for (final branch in [inbox, timeline, atlas, graph, notebooks])
          branch: tester
              .widget<ListTile>(find.byKey(ValueKey('nav-step-item-$branch')))
              .selected,
      };
      expect(selected, {
        inbox: false,
        timeline: false,
        atlas: true,
        graph: false,
        notebooks: false,
      });
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
        es.navTimeline,
        es.navAtlas,
        es.navMap,
        es.navNotebooks,
        es.navChat,
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
      expect(rail.selectedIndex, 3);
    });

    testWidgets('en el riel, tocar la línea de tiempo (F40) la abre, arriba '
        'del Atlas, y la marca', (tester) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();

      expect(find.byType(TimelineScreen), findsOneWidget);
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
