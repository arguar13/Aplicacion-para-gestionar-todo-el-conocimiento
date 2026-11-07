import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/back_navigation.dart';
import 'package:sinapsis/core/design/widgets/app_bottom_sheet.dart';

/// El nombre que ve el panel: la raíz dice uno, y una rama lo sobrescribe.
final _who = Provider<String>((ref) => 'la raíz');

/// El panel común (F46, paso 5j, decisión 1b): se abre en el navegador de la
/// raíz, encima de la barra de pestañas, con lo que repetía cada llamada.
void main() {
  // Un teléfono: 400 × 800, con un píxel por punto.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Un shell como el de la app: dos pestañas, cada una con su navegador, y
  /// la barra abajo. La segunda pestaña sobrescribe [_who] y abre el panel.
  GoRouter buildRouter(WidgetBuilder sheet, {List<Object?>? results}) =>
      GoRouter(
        initialLocation: '/biblioteca',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => BackToLibrary(
              navigationShell: shell,
              child: Scaffold(
                body: shell,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: shell.goBranch,
                  destinations: const [
                    NavigationDestination(
                      key: ValueKey('tab-biblioteca'),
                      icon: Icon(Icons.home),
                      label: 'Biblioteca',
                    ),
                    NavigationDestination(
                      key: ValueKey('tab-estudiar'),
                      icon: Icon(Icons.school),
                      label: 'Estudiar',
                    ),
                  ],
                ),
              ),
            ),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/biblioteca',
                    builder: (context, state) => const Text('biblioteca'),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/estudiar',
                    builder: (context, state) => ProviderScope(
                      overrides: [_who.overrideWithValue('la rama')],
                      child: Builder(
                        builder: (context) => TextButton(
                          onPressed: () async {
                            final result = await showAppBottomSheet<Object?>(
                              context: context,
                              builder: sheet,
                            );
                            results?.add(result);
                          },
                          child: const Text('abrir panel'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  Future<GoRouter> pumpShell(
    WidgetTester tester,
    WidgetBuilder sheet, {
    List<Object?>? results,
  }) async {
    phone(tester);
    final router = buildRouter(sheet, results: results);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    router.go('/estudiar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir panel'));
    await tester.pumpAndSettle();
    return router;
  }

  Widget plainSheet(BuildContext context) =>
      const SizedBox(height: 120, child: Text('el panel'));

  group('en el navegador de la raíz', () {
    testWidgets('abierto desde una pestaña, queda en el navegador de la raíz '
        'y su sombreado tapa la pantalla entera, la barra también', (
      tester,
    ) async {
      final router = await pumpShell(tester, plainSheet);

      final sheetNavigator = Navigator.of(
        tester.element(find.text('el panel')),
      );
      expect(sheetNavigator, router.routerDelegate.navigatorKey.currentState);
      final barrier = find.byWidgetPredicate(
        (w) => w is ModalBarrier && w.dismissible,
      );
      expect(tester.getRect(barrier.last), const Rect.fromLTWH(0, 0, 400, 800));
      expect(
        tester
            .getRect(barrier.last)
            .contains(tester.getCenter(find.byType(NavigationBar))),
        isTrue,
      );
    });

    testWidgets('la barra no recibe toques: tocarla cierra el panel, sin '
        'cambiar de pestaña', (tester) async {
      await pumpShell(tester, plainSheet);

      await tester.tap(
        find.byKey(const ValueKey('tab-biblioteca')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('el panel'), findsNothing);
      expect(find.text('abrir panel'), findsOneWidget);
      expect(find.text('biblioteca'), findsNothing);
    });

    testWidgets('«atrás» lo cierra antes que nada, y recién después lleva a la '
        'Biblioteca', (tester) async {
      await pumpShell(tester, plainSheet);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('el panel'), findsNothing);
      expect(find.text('abrir panel'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('biblioteca'), findsOneWidget);
    });

    testWidgets('Navigator.pop con el contexto del panel lo cierra y devuelve '
        'lo elegido', (tester) async {
      final results = <Object?>[];
      await pumpShell(
        tester,
        (context) => TextButton(
          onPressed: () => Navigator.of(context).pop('elegido'),
          child: const Text('elegir'),
        ),
        results: results,
      );

      await tester.tap(find.text('elegir'));
      await tester.pumpAndSettle();

      expect(find.text('elegir'), findsNothing);
      expect(find.text('abrir panel'), findsOneWidget);
      expect(results, ['elegido']);
    });

    testWidgets('ve los proveedores de la pestaña que lo abrió, con lo que '
        'sobrescribe', (tester) async {
      await pumpShell(
        tester,
        (context) => Consumer(
          builder: (context, ref, _) => Text('lo ve ${ref.watch(_who)}'),
        ),
      );

      expect(find.text('lo ve la rama'), findsOneWidget);
    });

    testWidgets('y sin un ProviderScope propio, el de la raíz', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  builder: (context) => Consumer(
                    builder: (context, ref, _) =>
                        Text('lo ve ${ref.watch(_who)}'),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('lo ve la raíz'), findsOneWidget);
    });
  });

  group('lo que repetía cada llamada', () {
    /// Una pantalla sola que abre el panel con [open].
    Future<void> pumpOpen(
      WidgetTester tester,
      Future<void> Function(BuildContext context) open,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => open(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('el teclado no lo tapa, y lo de adentro no lo vuelve a dejar', (
      tester,
    ) async {
      addTearDown(tester.view.resetViewInsets);
      double? seen;
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          builder: (context) {
            seen = MediaQuery.viewInsetsOf(context).bottom;
            return const TextField(key: Key('campo'));
          },
        ),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(const Key('campo'))).bottom, 500);
      expect(seen, 0);
      // La superficie del panel llega abajo, debajo del teclado.
      expect(tester.getRect(find.byType(BottomSheet)).bottom, 800);
    });

    testWidgets('no se mete debajo de la barra del sistema: lo de adentro '
        'queda arriba, y la superficie llega al borde', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          builder: (context) =>
              const SizedBox(key: Key('contenido'), height: 100),
        ),
      );

      expect(tester.getRect(find.byKey(const Key('contenido'))).bottom, 776);
      expect(tester.getRect(find.byType(BottomSheet)).bottom, 800);
    });

    testWidgets('con la manija de Material 3', (tester) async {
      await pumpOpen(
        tester,
        (context) =>
            showAppBottomSheet<void>(context: context, builder: plainSheet),
      );
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
    });

    testWidgets('sin manija si se pide', (tester) async {
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          showDragHandle: false,
          builder: plainSheet,
        ),
      );
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
    });

    testWidgets('el alto lo pone lo de adentro: uno largo llega hasta arriba, '
        'no a los nueve dieciséis', (tester) async {
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          builder: (context) => ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 48, child: Text('renglón $i')),
            ],
          ),
        ),
      );

      expect(
        tester.getRect(find.byType(BottomSheet)).height,
        greaterThan(800 * 9 / 16),
      );
    });

    testWidgets('con un alto máximo, una parte de la pantalla', (tester) async {
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          maxHeightFactor: 0.5,
          builder: (context) => ListView(
            key: const Key('lista'),
            shrinkWrap: true,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 48, child: Text('renglón $i')),
            ],
          ),
        ),
      );

      expect(tester.getRect(find.byKey(const Key('lista'))).height, 400);
    });

    testWidgets('un panel con su propia superficie: el del panel transparente, '
        'sin manija ni borde seguro agregado', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.resetPadding);
      await pumpOpen(
        tester,
        (context) => showAppBottomSheet<void>(
          context: context,
          ownSurface: true,
          builder: (context) => const ColoredBox(
            key: Key('superficie'),
            color: Colors.red,
            child: SizedBox(height: 100, width: double.infinity),
          ),
        ),
      );

      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.backgroundColor, Colors.transparent);
      expect(sheet.showDragHandle, isFalse);
      expect(tester.getRect(find.byKey(const Key('superficie'))).bottom, 800);
    });

    testWidgets('con «quitar animaciones», aparece sin deslizarse', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              disableAnimations: true,
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showAppBottomSheet<void>(
                    context: context,
                    builder: plainSheet,
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump();

      expect(tester.getRect(find.byType(BottomSheet)).bottom, 800);
    });
  });
}
