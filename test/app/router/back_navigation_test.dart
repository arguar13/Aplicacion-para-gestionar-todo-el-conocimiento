import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/back_navigation.dart';

/// El caso del teléfono del usuario: una pestaña con su propio navegador,
/// un elemento abierto adentro, y un diálogo que se abre y se cierra sobre
/// él (F22, "Volver a extraer").
void main() {
  late List<bool> reported;
  // Las veces que la app le devolvió «atrás» al sistema: salir.
  late int systemPops;

  setUp(() {
    reported = [];
    systemPops = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            reported.add(call.arguments as bool);
          }
          if (call.method == 'SystemNavigator.pop') systemPops++;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/biblioteca',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/biblioteca',
                builder: (context, state) => TextButton(
                  onPressed: () => context.push('/biblioteca/audio'),
                  child: const Text('abrir'),
                ),
                routes: [
                  GoRoute(
                    path: 'audio',
                    builder: (context, state) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('confirmar'),
                        ),
                      ),
                      child: const Text('volver a extraer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bandeja',
                builder: (context, state) => const Text('bandeja'),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> openItemAndCloseADialog(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('volver a extraer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('confirmar'));
    await tester.pumpAndSettle();
  }

  testWidgets('cerrado el diálogo, "atrás" lo sigue manejando la app: '
      'vuelve a la biblioteca en vez de minimizarla', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        onNavigationNotification: (notification) =>
            reportBackHandling(router, notification),
      ),
    );

    await openItemAndCloseADialog(tester);

    expect(reported.last, isTrue);
  });

  testWidgets('sin esto, Flutter le decía a Android que no: el defecto que '
      'se corrige', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await openItemAndCloseADialog(tester);

    expect(reported.last, isFalse);
  });

  testWidgets('en la biblioteca misma, "atrás" sí es del sistema', (
    tester,
  ) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        onNavigationNotification: (notification) =>
            reportBackHandling(router, notification),
      ),
    );

    await openItemAndCloseADialog(tester);
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('abrir'), findsOneWidget);
    expect(reported.last, isFalse);
  });

  // Visto en el emulador: desde Estudiar › Línea de tiempo —la raíz de su
  // rama—, «atrás» minimizaba la app. La pauta de Android: desde un destino
  // principal que no es el de inicio, «atrás» va al de inicio, y recién desde
  // ahí sale.
  group('«atrás» en la entrada de una pestaña lleva a la Biblioteca (F46, '
      'paso 5h)', () {
    /// Biblioteca, Bandeja y Línea de tiempo, como en la app: el shell
    /// envuelto en [BackToLibrary]. La línea de tiempo tiene una pantalla
    /// adentro, y desde su entrada se abre un diálogo o una hoja de abajo.
    GoRouter buildShellRouter() => GoRouter(
      initialLocation: '/biblioteca',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => BackToLibrary(
            navigationShell: shell,
            child: Scaffold(body: shell),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/biblioteca',
                  builder: (context, state) => TextButton(
                    onPressed: () => context.push('/biblioteca/nota'),
                    child: const Text('biblioteca'),
                  ),
                  routes: [
                    GoRoute(
                      path: 'nota',
                      builder: (context, state) => const Text('una nota'),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/bandeja',
                  builder: (context, state) => const Text('bandeja'),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/linea',
                  builder: (context, state) => Column(
                    children: [
                      const Text('línea de tiempo'),
                      TextButton(
                        onPressed: () => context.push('/linea/evento'),
                        child: const Text('abrir evento'),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => const Text('un diálogo'),
                        ),
                        child: const Text('abrir diálogo'),
                      ),
                      TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (context) => const Text('una hoja'),
                        ),
                        child: const Text('abrir hoja'),
                      ),
                    ],
                  ),
                  routes: [
                    GoRoute(
                      path: 'evento',
                      builder: (context, state) => const Text('un evento'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    Future<GoRouter> pumpShell(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final router = buildShellRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          onNavigationNotification: (notification) =>
              reportBackHandling(router, notification),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    /// «Atrás» de Android: el botón o el gesto.
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    for (final (path, name) in [
      ('/bandeja', 'bandeja'),
      ('/linea', 'línea de tiempo'),
    ]) {
      testWidgets('desde la entrada de «$name», va a la Biblioteca sin salir', (
        tester,
      ) async {
        final router = await pumpShell(tester);
        router.go(path);
        await tester.pumpAndSettle();

        // Android sabe que «atrás» es de la app, aunque no haya nada encima.
        expect(reported.last, isTrue);

        await back(tester);

        expect(find.text('biblioteca'), findsOneWidget);
        expect(find.text(name), findsNothing);
        expect(systemPops, 0);
      });
    }

    testWidgets('desde la Biblioteca, sin nada encima, es del sistema: sale', (
      tester,
    ) async {
      final router = await pumpShell(tester);
      router.go('/bandeja');
      await tester.pumpAndSettle();
      await back(tester);
      expect(reported.last, isFalse);

      await back(tester);

      expect(systemPops, 1);
    });

    testWidgets('dentro de una pestaña, «atrás» vuelve a la pantalla de antes '
        'como siempre, y recién después va a la Biblioteca', (tester) async {
      final router = await pumpShell(tester);
      router.go('/linea');
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir evento'));
      await tester.pumpAndSettle();
      expect(find.text('un evento'), findsOneWidget);

      await back(tester);

      expect(find.text('línea de tiempo'), findsOneWidget);
      // La pila de la pestaña avisó que ya no tiene nada que cerrar, y aun
      // así «atrás» sigue siendo de la app: falta ir a la Biblioteca.
      expect(reported.last, isTrue);

      await back(tester);

      expect(find.text('biblioteca'), findsOneWidget);
      expect(systemPops, 0);
    });

    for (final (open, shown) in [
      ('abrir diálogo', 'un diálogo'),
      ('abrir hoja', 'una hoja'),
    ]) {
      testWidgets('con «$shown» abierto, «atrás» lo cierra primero', (
        tester,
      ) async {
        final router = await pumpShell(tester);
        router.go('/linea');
        await tester.pumpAndSettle();
        await tester.tap(find.text(open));
        await tester.pumpAndSettle();
        expect(find.text(shown), findsOneWidget);

        await back(tester);

        expect(find.text(shown), findsNothing);
        expect(find.text('línea de tiempo'), findsOneWidget);
        expect(reported.last, isTrue);

        await back(tester);

        expect(find.text('biblioteca'), findsOneWidget);
        expect(systemPops, 0);
      });
    }

    testWidgets('la Biblioteca vuelve con lo que tenía abierto, y desde ahí '
        '«atrás» lo cierra antes de salir', (tester) async {
      final router = await pumpShell(tester);
      await tester.tap(find.text('biblioteca'));
      await tester.pumpAndSettle();
      router.go('/bandeja');
      await tester.pumpAndSettle();

      await back(tester);

      expect(find.text('una nota'), findsOneWidget);
      expect(reported.last, isTrue);

      await back(tester);

      expect(find.text('biblioteca'), findsOneWidget);
      expect(systemPops, 0);
      expect(reported.last, isFalse);
    });
  });
}
