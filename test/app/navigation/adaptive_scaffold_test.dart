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
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/features/atlas/presentation/screens/atlas_screen.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_entry_screen.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/unsorted_items_screen.dart';
import 'package:sinapsis/features/map/presentation/screens/map_screen.dart';
import 'package:sinapsis/features/notebooks/presentation/screens/notebooks_screen.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_screen.dart';
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
  final processed = ShellBranch.processed.index;
  final timeline = ShellBranch.timeline.index;
  final atlas = ShellBranch.atlas.index;
  final graph = ShellBranch.graph.index;
  final notebooks = ShellBranch.notebooks.index;
  final review = ShellBranch.review.index;
  final es = AppLocalizationsEs();
  late SharedPreferences prefs;

  setUp(() async {
    EnvConfig.initialize(AppFlavor.dev);
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildRoutedApp(ProviderContainer container, {ThemeData? theme}) {
    return UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: theme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(goRouterProvider),
        ),
      ),
    );
  }

  ProviderContainer buildUnlockedContainer({
    List<Override> overrides = const [],
  }) {
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
        ...overrides,
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

  /// Las claves de los renglones de la lista abierta, de arriba abajo.
  List<String> sheetItemKeys(WidgetTester tester) => [
    for (final t in tester.widgetList<ListTile>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
    ))
      (t.key! as ValueKey<String>).value,
  ];

  /// La insignia del botón del paso [step] en la barra.
  Badge stepBadge(WidgetTester tester, String step) => tester.widget<Badge>(
    find.descendant(
      of: find.byKey(ValueKey('nav-step-$step')),
      matching: find.byType(Badge),
    ),
  );

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
      'la barra son los cinco pasos en orden de uso —Biblioteca, Organizar, '
      'Estudiar, Chat y Ajustes (F43)—, sin «Más»',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();

        final destinations = tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .toList();
        expect(
          [for (final d in destinations) d.label],
          ['Biblioteca', 'Organizar', 'Estudiar', 'Chat', 'Ajustes'],
        );
        expect(
          [for (final d in destinations) (d.key! as ValueKey<String>).value],
          [
            'nav-step-save',
            'nav-step-organize',
            'nav-step-study',
            'nav-step-ask',
            'nav-step-settings',
          ],
        );
        expect(find.byIcon(Icons.more_horiz), findsNothing);
        // Repasar ya no es un botón: está en la lista de «Estudiar».
        expect(find.text(es.navReview), findsNothing);
      },
    );

    // Cada destino de un paso con lista: su rama, la pantalla que abre y la
    // posición del paso en la barra.
    final listed = [
      (step: 'organize', branch: inbox, screen: InboxScreen, barIndex: 1),
      (step: 'organize', branch: atlas, screen: AtlasScreen, barIndex: 1),
      (step: 'study', branch: processed, screen: ProcessedScreen, barIndex: 2),
      (step: 'study', branch: notebooks, screen: NotebooksScreen, barIndex: 2),
      (step: 'study', branch: timeline, screen: TimelineScreen, barIndex: 2),
      (step: 'study', branch: graph, screen: MapScreen, barIndex: 2),
      (step: 'study', branch: review, screen: ReviewEntryScreen, barIndex: 2),
    ];

    testWidgets(
      '«Organizar» abre su lista: la Bandeja y el Atlas, en ese orden y con '
      'para qué sirve cada uno',
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
        expect(sheetItemKeys(tester), [
          'nav-step-item-$inbox',
          'nav-step-item-$atlas',
        ]);
        for (final hint in [es.navInboxHint, es.navAtlasHint]) {
          expect(
            find.descendant(of: sheet, matching: find.text(hint)),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      '«Estudiar» (F43) abre su lista: Procesado, Cuadernos, Línea de tiempo, '
      'Mapa y Repasar, en ese orden y con para qué sirve cada uno',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-step-study')));
        await tester.pumpAndSettle();

        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('Estudiar')),
          findsOneWidget,
        );
        expect(sheetItemKeys(tester), [
          for (final branch in [processed, notebooks, timeline, graph, review])
            'nav-step-item-$branch',
        ]);
        for (final text in [
          es.navProcessed,
          es.navProcessedHint,
          es.navNotebooks,
          es.navNotebooksHint,
          es.navTimeline,
          es.navTimelineHint,
          es.navMap,
          es.navMapHint,
          'Repasar',
          es.navReviewHint,
        ]) {
          expect(
            find.descendant(of: sheet, matching: find.text(text)),
            findsOneWidget,
            reason: text,
          );
        }
      },
    );

    testWidgets(
      'el número de tarjetas para hoy se ve en «Estudiar», y el de la Bandeja '
      'en «Organizar» (F43)',
      (tester) async {
        setLogicalWidth(tester, 400);

        await tester.pumpWidget(
          buildRoutedApp(
            buildUnlockedContainer(
              overrides: [
                studyDueTodayCountProvider.overrideWith(
                  (ref) => const AsyncData(4),
                ),
                inboxPendingIdsProvider.overrideWith(
                  (ref) => Stream.value(const ['a', 'b']),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final study = stepBadge(tester, 'study');
        expect(study.isLabelVisible, isTrue);
        expect((study.label! as Text).data, '4');
        final organize = stepBadge(tester, 'organize');
        expect(organize.isLabelVisible, isTrue);
        expect((organize.label! as Text).data, '2');

        // Adentro de la lista, Repasar muestra la suya.
        await tester.tap(find.byKey(const ValueKey('nav-step-study')));
        await tester.pumpAndSettle();
        final inList = tester.widget<Badge>(
          find.descendant(
            of: find.byKey(ValueKey('nav-step-item-$review')),
            matching: find.byType(Badge),
          ),
        );
        expect((inList.label! as Text).data, '4');
      },
    );

    testWidgets('el chat, a la derecha de «Estudiar», se abre directo, sin '
        'lista, y queda marcado', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-step-ask')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 3);
    });

    testWidgets(
      'con el teclado abierto la barra se va y el chat usa toda la altura; '
      'vuelve al cerrarlo (F42)',
      (tester) async {
        setLogicalWidth(tester, 400);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-step-ask')));
        await tester.pumpAndSettle();
        final withBar = tester.getRect(find.byType(ChatScreen));

        // El teclado sube: mientras todavía no la tapa entera, la barra
        // sigue, y lo de arriba no salta.
        tester.view.viewInsets = const FakeViewPadding(bottom: 40);
        await tester.pump();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.getRect(find.byType(ChatScreen)), withBar);

        // Ya la tapa: la barra se va y el chat llega hasta el teclado.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(tester.getRect(find.byType(ChatScreen)).bottom, 800 - 300);

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.getRect(find.byType(ChatScreen)), withBar);
      },
    );

    testWidgets('justo cuando el teclado llega al alto de la barra, se va', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 79);
      await tester.pump();
      expect(find.byType(NavigationBar), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 80);
      await tester.pump();
      expect(find.byType(NavigationBar), findsNothing);
    });

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

    testWidgets('Biblioteca y Ajustes abren directo, sin lista, y quedan '
        'marcados', (tester) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      for (final (step, screen, barIndex) in [
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
    });

    testWidgets('la lista marca el destino que está abierto, y solo ese', (
      tester,
    ) async {
      setLogicalWidth(tester, 400);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-step-study')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('nav-step-item-$timeline')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-step-study')));
      await tester.pumpAndSettle();

      final selected = {
        for (final branch in [processed, notebooks, timeline, graph, review])
          branch: tester
              .widget<ListTile>(find.byKey(ValueKey('nav-step-item-$branch')))
              .selected,
      };
      expect(selected, {
        processed: false,
        notebooks: false,
        timeline: true,
        graph: false,
        review: false,
      });
    });

    testWidgets('a 360 de ancho y con la letra al doble, la barra y la lista '
        'de «Estudiar» entran sin desbordar', (tester) async {
      setLogicalWidth(tester, 360);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        buildRoutedApp(
          buildUnlockedContainer(
            overrides: [
              studyDueTodayCountProvider.overrideWith(
                (ref) => const AsyncData(128),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('nav-step-study')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-step-study')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // La lista se desplaza: el último, Repasar, se alcanza entero, dentro
      // de la pantalla. (Abrirlo no es de esta prueba: cómo se ve Repasar
      // con letra grande es cosa de su pantalla.)
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('nav-step-item-$review')),
        100,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final tile = tester.getRect(
        find.byKey(ValueKey('nav-step-item-$review')),
      );
      expect(tile.left, greaterThanOrEqualTo(0));
      expect(tile.right, lessThanOrEqualTo(360));
      expect(tile.bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
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

    testWidgets('el riel muestra los diez destinos en el orden de la barra '
        '(F43): Organizar, Estudiar y después el chat', (tester) async {
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
        es.navProcessed,
        es.navNotebooks,
        es.navTimeline,
        es.navMap,
        es.navReview,
        es.navChat,
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

    testWidgets('en el riel, tocar la línea de tiempo (F40) la abre, debajo '
        'de los cuadernos, y la marca', (tester) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.timeline));
      await tester.pumpAndSettle();

      expect(find.byType(TimelineScreen), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 5);
    });

    testWidgets('en el riel, tocar Procesado (F41) lo abre, después del Atlas, '
        'y lo marca', (tester) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.summarize_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(ProcessedScreen), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 3);
    });

    testWidgets('en el riel, tocar Repasar lo abre, antes del chat, y lo '
        'marca', (tester) async {
      setLogicalWidth(tester, 1200);

      await tester.pumpWidget(buildRoutedApp(buildUnlockedContainer()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(es.navReview),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ReviewEntryScreen), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 7);
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

  group('«Organizar», con lo que quedó sin tema (F45, mejora 17)', () {
    final task = find.byKey(const ValueKey('unsorted-task'));

    /// La app en un teléfono, con [unsorted] elementos sin tema, y la lista
    /// de [step] abierta.
    Future<void> openStep(
      WidgetTester tester, {
      required int unsorted,
      String step = 'organize',
      double width = 400,
      ThemeData? theme,
    }) async {
      setLogicalWidth(tester, width);
      await tester.pumpWidget(
        buildRoutedApp(
          buildUnlockedContainer(
            overrides: [
              unsortedCountProvider.overrideWith(
                (ref) => Stream.value(unsorted),
              ),
            ],
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('nav-step-$step')));
      await tester.pumpAndSettle();
    }

    testWidgets('la cuenta es una tarea más, debajo de la Bandeja y el Atlas, '
        'y «Ordenarlos» cierra la lista y abre la de lo que no tiene tema', (
      tester,
    ) async {
      await openStep(tester, unsorted: 49);

      final sheet = find.byType(BottomSheet);
      expect(find.descendant(of: sheet, matching: task), findsOneWidget);
      expect(
        find.descendant(
          of: task,
          matching: find.text(es.libraryUnsortedTitle(49)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: task, matching: find.text(es.libraryUnsortedBody)),
        findsOneWidget,
      );
      // Las pantallas del paso siguen siendo dos, y la tarea va después.
      expect(sheetItemKeys(tester), [
        'nav-step-item-$inbox',
        'nav-step-item-$atlas',
      ]);
      expect(
        tester.getTopLeft(task).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(ValueKey('nav-step-item-$atlas'))).dy,
        ),
      );

      await tester.tap(find.text(es.libraryUnsortedAction));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(UnsortedItemsScreen), findsOneWidget);
    });

    testWidgets('sin nada sin tema, la lista es solo la Bandeja y el Atlas', (
      tester,
    ) async {
      await openStep(tester, unsorted: 0);

      expect(task, findsNothing);
      expect(find.text(es.libraryUnsortedAction), findsNothing);
    });

    testWidgets('«Estudiar» no la muestra: no es donde se ordena', (
      tester,
    ) async {
      await openStep(tester, unsorted: 49, step: 'study');

      expect(task, findsNothing);
    });

    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('a 360 dp con la letra al doble, tema $name: la tarea entra '
          'entera en la lista, sin desbordar', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openStep(tester, unsorted: 49, width: 360, theme: theme);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.byKey(const Key('unsorted-task-open')),
          100,
          scrollable: find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(task);
        final action = tester.getRect(
          find.byKey(const Key('unsorted-task-open')),
        );
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(360));
        expect(action.right, lessThanOrEqualTo(card.right));
        expect(action.bottom, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el lector de pantalla la lee junta —la cuenta y para qué— y '
        '«Ordenarlos» como un botón', (tester) async {
      final handle = tester.ensureSemantics();
      await openStep(tester, unsorted: 49);

      expect(
        tester.getSemantics(task),
        isSemantics(
          label: '${es.libraryUnsortedTitle(49)}\n${es.libraryUnsortedBody}',
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('unsorted-task-open'))),
        isSemantics(
          label: es.libraryUnsortedAction,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
