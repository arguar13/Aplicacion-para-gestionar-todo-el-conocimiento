import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/navigation/adaptive_scaffold.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/design/widgets/snack_bar_footprint.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../support/fake_text_to_speech_service.dart';

/// Un lector que ya está sonando, achicado, sin motor de voz detrás.
class _Reading extends ReadAloudController {
  @override
  ReadAloudState build() => const ReadAloudState(
    document: ReadableDocument(
      id: 'item-1',
      title: 'Fotosíntesis',
      segments: [
        ReadableSegment(
          sourceKey: 'texto',
          start: 0,
          end: 10,
          spoken: '0123456789',
        ),
      ],
    ),
    playing: true,
    panel: ReadAloudPanel.minimized,
  );
}

/// El lugar del reproductor en el shell de verdad (F46, paso 5i): las
/// pestañas de `AdaptiveScaffold`, cada una con su navegador, y el lector
/// encima de todo, como en `App`. En el emulador, en Ajustes y con el
/// reproductor achicado sonando, la hoja «Aspecto de lectura» —que se abre en
/// el navegador de la pestaña, adentro del cuerpo que el reproductor
/// achicaba— escondía el reproductor pero no le devolvía su lugar: terminaba
/// unos 190 px reales arriba de la barra, con una franja del color de la
/// página y sin el sombreado del panel.
void main() {
  const phone = Size(400, 800);
  final collapsed = find.byKey(const Key('read-aloud-collapsed'));
  final body = find.byKey(const Key('cuerpo-de-la-pestaña'));
  final bar = find.byType(NavigationBar);

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      initialLocation: '/ajustes',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              AdaptiveScaffold(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/ajustes',
                  builder: (_, _) => Scaffold(
                    body: SizedBox.expand(
                      key: const Key('cuerpo-de-la-pestaña'),
                      child: Builder(
                        // Como «Aspecto de lectura»: una hoja abierta desde
                        // la pestaña, en el navegador de su rama.
                        builder: (context) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (_) => const SizedBox(
                                  height: 240,
                                  child: Text('Aspecto de lectura'),
                                ),
                              ),
                              child: const Text('Aa'),
                            ),
                            // Lo mismo en el navegador de la raíz, como van
                            // a abrirse las hojas (paso 5j).
                            TextButton(
                              onPressed: () => showModalBottomSheet<void>(
                                context: context,
                                useRootNavigator: true,
                                builder: (_) => const SizedBox(
                                  height: 240,
                                  child: Text('Hoja en la raíz'),
                                ),
                              ),
                              child: const Text('raíz'),
                            ),
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                useRootNavigator: false,
                                builder: (_) => const AlertDialog(
                                  content: Text('Un diálogo'),
                                ),
                              ),
                              child: const Text('diálogo'),
                            ),
                            PopupMenuButton<int>(
                              key: const Key('menú'),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 1, child: Text('Uno')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/otra',
                  builder: (_, _) => const Scaffold(body: Text('Otra')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(
          FakeTextToSpeechService(),
        ),
        narrationVoicesProvider.overrideWith((ref) async => const []),
        readAloudControllerProvider.overrideWith(_Reading.new),
        studyDueTodayCountProvider.overrideWith((ref) => const AsyncData(0)),
        inboxPendingIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => SnackBarFootprintHost(
            child: ReadAloudOverlay(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// El sombreado del panel: la barrera de la ruta de arriba del navegador
  /// de la pestaña, la única que tiene color.
  Finder shade() => find.byWidgetPredicate(
    (widget) => widget is ModalBarrier && widget.color != null,
  );

  testWidgets('con el reproductor sonando, la pestaña le deja su lugar encima '
      'de la barra', (tester) async {
    await pump(tester);

    expect(collapsed, findsOneWidget);
    expect(tester.getRect(collapsed).bottom, tester.getRect(bar).top);
    expect(tester.getRect(body).bottom, tester.getRect(collapsed).top);
  });

  testWidgets('una hoja abierta en la pestaña llega hasta la barra, y su '
      'sombreado cubre todo el cuerpo: no queda una franja', (tester) async {
    await pump(tester);
    final barTop = tester.getRect(bar).top;

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();

    expect(find.text('Aspecto de lectura'), findsOneWidget);
    // El reproductor se hace a un lado…
    expect(collapsed, findsNothing);
    // …y su lugar se va con él: la hoja termina en la barra.
    expect(tester.getRect(find.byType(BottomSheet)).bottom, barTop);
    expect(tester.getRect(body).bottom, barTop);
    final shaded = tester.getRect(shade());
    expect(shaded.top, 0);
    expect(shaded.bottom, barTop);
    // La barra sigue a la vista, debajo.
    expect(tester.getRect(bar).bottom, phone.height);
  });

  testWidgets('al cerrarla, el reproductor vuelve y su lugar con él', (
    tester,
  ) async {
    await pump(tester);
    final before = tester.getRect(body).bottom;

    await tester.tap(find.text('Aa'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Aspecto de lectura'))).pop();
    await tester.pumpAndSettle();

    expect(collapsed, findsOneWidget);
    expect(tester.getRect(body).bottom, before);
    expect(tester.getRect(body).bottom, tester.getRect(collapsed).top);
  });

  testWidgets('una hoja abierta en la raíz tapa también la barra, con su '
      'sombreado sobre toda la pantalla, y al cerrarla el lugar vuelve', (
    tester,
  ) async {
    await pump(tester);
    final before = tester.getRect(body).bottom;

    await tester.tap(find.text('raíz'));
    await tester.pumpAndSettle();

    expect(collapsed, findsNothing);
    expect(tester.getRect(find.byType(BottomSheet)).bottom, phone.height);
    final shaded = tester.getRect(shade());
    expect(shaded.top, 0);
    expect(shaded.bottom, phone.height);
    // Debajo, la pestaña ya no le guarda lugar a un reproductor escondido.
    expect(tester.getRect(body).bottom, tester.getRect(bar).top);

    Navigator.of(tester.element(find.text('Hoja en la raíz'))).pop();
    await tester.pumpAndSettle();
    expect(collapsed, findsOneWidget);
    expect(tester.getRect(body).bottom, before);
  });

  for (final (name, open, shown) in [
    ('un diálogo', 'diálogo', 'Un diálogo'),
    ('un menú', null, 'Uno'),
  ]) {
    testWidgets('$name abierto en la pestaña también suelta el lugar, y al '
        'cerrarse vuelve', (tester) async {
      await pump(tester);
      final before = tester.getRect(body).bottom;

      await tester.tap(
        open == null ? find.byKey(const Key('menú')) : find.text(open),
      );
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget);
      expect(collapsed, findsNothing);
      expect(tester.getRect(body).bottom, tester.getRect(bar).top);

      Navigator.of(tester.element(find.text(shown))).pop();
      await tester.pumpAndSettle();
      expect(collapsed, findsOneWidget);
      expect(tester.getRect(body).bottom, before);
    });
  }
}
