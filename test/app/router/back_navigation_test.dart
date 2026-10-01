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

  setUp(() {
    reported = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
            reported.add(call.arguments as bool);
          }
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
}
