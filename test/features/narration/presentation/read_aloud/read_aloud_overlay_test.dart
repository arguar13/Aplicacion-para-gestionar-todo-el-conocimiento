import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Un lector de mentira: anota qué se le pidió y se deja mover a mano, sin
/// motor de voz detrás. El lector flotante de verdad se prueba aparte; acá
/// importa que la pantalla le pida lo correcto y muestre lo que tiene.
class _FakeReadAloud extends ReadAloudController {
  _FakeReadAloud(this._initial);

  final ReadAloudState _initial;
  final calls = <String>[];

  @override
  ReadAloudState build() => _initial;

  @override
  Future<void> open(ReadableDocument document, {int fromSegment = 0}) async {
    calls.add('open ${document.id}');
    state = state.copyWith(
      document: document,
      panel: ReadAloudPanel.expanded,
      playing: true,
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    state = state.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> skip(Duration delta) async =>
      calls.add('skip ${delta.inSeconds}');

  @override
  Future<void> setSpeed(double speed) async {
    calls.add('speed ${speed.toStringAsFixed(2)}');
    state = state.copyWith(speed: speed);
  }

  @override
  Future<void> setVoice(NarrationVoice? voice) async {
    calls.add('voice ${voice?.name}');
    state = voice == null
        ? state.copyWith(clearVoice: true)
        : state.copyWith(voice: voice);
  }

  @override
  void minimize() {
    calls.add('minimize');
    state = state.copyWith(panel: ReadAloudPanel.minimized);
  }

  @override
  void expand() {
    calls.add('expand');
    state = state.copyWith(panel: ReadAloudPanel.expanded);
  }

  @override
  Future<void> close() async {
    calls.add('close');
    state = const ReadAloudState();
  }
}

const _document = ReadableDocument(
  id: 'item-1',
  title: 'Las ideas de Ada Lovelace',
  segments: [
    ReadableSegment(
      sourceKey: 'texto',
      start: 0,
      end: 10,
      spoken: '0123456789',
    ),
    ReadableSegment(
      sourceKey: 'texto',
      start: 11,
      end: 21,
      spoken: '0123456789',
    ),
  ],
);

const _reading = ReadAloudState(
  document: _document,
  playing: true,
  panel: ReadAloudPanel.expanded,
);

/// Un celular: la barra de navegación solo se ve debajo de los 600 de ancho.
const _phone = Size(400, 800);

void main() {
  final es = AppLocalizationsEs();
  late _FakeReadAloud reader;
  late ProviderContainer container;

  final button = find.byKey(const Key('read-aloud-button'));
  final player = find.byKey(const Key('read-aloud-player'));

  /// La app con el lector flotante encima, como en `App`. [screen] es la
  /// única pantalla; con [withBar], dentro de unas pestañas con barra de
  /// navegación abajo, y con una ruta `/arriba` que se abre por encima.
  Future<GoRouter> pump(
    WidgetTester tester, {
    ReadAloudState initial = const ReadAloudState(),
    ReadableDocument? offered,
    List<NarrationVoice> voices = const [],
    Widget screen = const Scaffold(body: Center(child: Text('Pantalla'))),
    bool withBar = false,
  }) async {
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    reader = _FakeReadAloud(initial);
    container = ProviderContainer(
      overrides: [
        readAloudControllerProvider.overrideWith(() => reader),
        narrationVoicesProvider.overrideWith((ref) async => voices),
      ],
    );
    addTearDown(container.dispose);
    if (offered != null) {
      container
          .read(readableRegistryProvider.notifier)
          .offer(Object(), offered);
    }

    final router = GoRouter(
      routes: [
        if (withBar)
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: child,
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'A'),
                  NavigationDestination(icon: Icon(Icons.chat), label: 'B'),
                ],
              ),
            ),
            routes: [GoRoute(path: '/', builder: (_, _) => screen)],
          )
        else
          GoRoute(path: '/', builder: (_, _) => screen),
        GoRoute(
          path: '/arriba',
          builder: (_, _) => const Scaffold(body: Text('Arriba')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ReadAloudOverlay(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  group('el botón redondo', () {
    testWidgets('no aparece si la pantalla no tiene texto para leer', (
      tester,
    ) async {
      await pump(tester);

      expect(button, findsNothing);
    });

    testWidgets('aparece con texto, y tocarlo empieza a leer ese texto', (
      tester,
    ) async {
      await pump(tester, offered: _document);
      expect(button, findsOneWidget);
      expect(find.byKey(const Key('read-aloud-ring')), findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(reader.calls, ['open item-1']);
      expect(player, findsOneWidget);
      expect(find.text(_document.title), findsOneWidget);
      expect(find.text(es.readAloudReading), findsOneWidget);
      // Con el reproductor abierto, el botón se fue.
      expect(button, findsNothing);
    });

    testWidgets('no se queda con los toques de la pantalla de abajo', (
      tester,
    ) async {
      var taps = 0;
      await pump(
        tester,
        offered: _document,
        screen: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Tocame'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tocame'));

      expect(taps, 1);
    });

    testWidgets('minimizado, muestra el anillo con cuánto leyó, y tocarlo '
        'abre el reproductor', (tester) async {
      await pump(
        tester,
        initial: _reading.copyWith(
          panel: ReadAloudPanel.minimized,
          segmentIndex: 1,
          charInSegment: 0,
        ),
      );

      // Sigue ahí aunque la pantalla no tenga texto: está leyendo.
      expect(button, findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byKey(const Key('read-aloud-ring')),
      );
      expect(ring.value, 0.5);
      expect(find.byKey(const Key('read-aloud-badge')), findsOneWidget);
      expect(player, findsNothing);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(reader.calls, ['expand']);
      expect(player, findsOneWidget);
    });

    testWidgets('se hace a un lado mientras el teclado está abierto', (
      tester,
    ) async {
      await pump(tester, offered: _document);
      expect(button, findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(button, findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
    });

    testWidgets('se para encima de la barra de navegación, y baja en una '
        'pantalla sin barra', (tester) async {
      final router = await pump(tester, offered: _document, withBar: true);
      const barHeight = 80.0;

      expect(tester.getRect(button).bottom, _phone.height - barHeight - 16);

      unawaited(router.push('/arriba'));
      await tester.pumpAndSettle();

      expect(tester.getRect(button).bottom, _phone.height - 16);
    });

    testWidgets('se para encima de lo que pide esquivar', (tester) async {
      await pump(
        tester,
        offered: _document,
        screen: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReadAloudClearance(child: SizedBox(height: 100)),
          ),
        ),
      );

      expect(tester.getRect(button).bottom, _phone.height - 100 - 12);
    });
  });

  group('el reproductor', () {
    testWidgets('pausa, reproduce, salta 10 s para los dos lados', (
      tester,
    ) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-play')));
      await tester.pumpAndSettle();
      expect(find.text(es.readAloudPaused), findsOneWidget);
      await tester.tap(find.byKey(const Key('read-aloud-play')));
      await tester.tap(find.byKey(const Key('read-aloud-replay')));
      await tester.tap(find.byKey(const Key('read-aloud-forward')));

      expect(reader.calls, ['pause', 'play', 'skip -10', 'skip 10']);
    });

    testWidgets('el avance se ve como un hilo', (tester) async {
      await pump(
        tester,
        initial: _reading.copyWith(segmentIndex: 0, charInSegment: 5),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('read-aloud-progress')),
      );
      expect(bar.value, 0.25);
    });

    testWidgets('minimizar lo deja como el botón con su anillo', (
      tester,
    ) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-minimize')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['minimize']);
      expect(player, findsNothing);
      expect(find.byKey(const Key('read-aloud-ring')), findsOneWidget);
    });

    testWidgets('cerrar deja de leer, y sin texto en pantalla no queda nada', (
      tester,
    ) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-close')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['close']);
      expect(player, findsNothing);
      expect(button, findsNothing);
    });

    testWidgets('si el motor de voz falla, lo dice', (tester) async {
      await pump(
        tester,
        initial: _reading.copyWith(playing: false, failed: true),
      );

      expect(find.text(es.readAloudFailed), findsOneWidget);
    });
  });

  group('el panel de la velocidad', () {
    testWidgets('cambia la velocidad a un toque y con el ajuste fino', (
      tester,
    ) async {
      await pump(tester, initial: _reading);
      expect(find.text('1×'), findsOneWidget);

      await tester.tap(find.byKey(const Key('read-aloud-speed')));
      await tester.pumpAndSettle();
      // Con el panel abierto, el reproductor se hace a un lado.
      expect(player, findsNothing);

      await tester.tap(find.byKey(const Key('read-aloud-speed-1.5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('read-aloud-speed-up')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['speed 1.50', 'speed 1.55']);
      expect(find.byKey(const Key('read-aloud-speed-2.0')), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-speed-0.25')), findsNothing);
    });
  });

  group('el panel de voz y acento', () {
    const argentina = NarrationVoice(
      name: 'es-ar-x-ara-local',
      locale: 'es-AR',
    );
    const argentinaOnline = NarrationVoice(
      name: 'es-ar-x-ara-network',
      locale: 'es-AR',
    );
    const spain = NarrationVoice(name: 'Mónica', locale: 'es_ES');
    const unitedStates = NarrationVoice(
      name: 'en-us-x-sfg-local',
      locale: 'en-US',
    );
    const voices = [unitedStates, argentinaOnline, spain, argentina];

    Future<void> openSheet(WidgetTester tester, {NarrationVoice? voice}) async {
      await pump(
        tester,
        initial: _reading.copyWith(voice: voice),
        voices: voices,
      );
      await tester.tap(find.byKey(const Key('read-aloud-voice')));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra los acentos por su nombre, los del idioma de la app '
        'primero, y las voces del acento de la voz elegida', (tester) async {
      await openSheet(tester, voice: argentina);

      final accents = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data)
          .toList();
      expect(accents, [
        'Español (Argentina)',
        'Español (España)',
        'English (United States)',
      ]);
      // Las de Argentina: primero la que anda sin conexión.
      expect(find.text(es.readAloudVoiceNumber(1)), findsOneWidget);
      expect(find.text(es.readAloudVoiceOnDevice), findsOneWidget);
      expect(find.text(es.readAloudVoiceNumber(2)), findsOneWidget);
      expect(find.text(es.readAloudVoiceNeedsInternet), findsOneWidget);
    });

    testWidgets('elegir un acento lee con su voz, y se puede elegir otra', (
      tester,
    ) async {
      await openSheet(tester, voice: argentina);

      for (final accent in ['English (United States)', 'Español (España)']) {
        await tester.ensureVisible(find.text(accent));
        await tester.tap(find.text(accent));
        await tester.pumpAndSettle();
      }
      // Una voz con nombre de verdad se muestra tal cual.
      await tester.tap(find.text('Mónica'));
      await tester.pumpAndSettle();

      // Mónica ya era la elegida: tocarla de nuevo no pide nada.
      expect(reader.calls, ['voice en-us-x-sfg-local', 'voice Mónica']);
    });

    testWidgets('elegir la voz del sistema vuelve a la del teléfono', (
      tester,
    ) async {
      await openSheet(tester, voice: argentina);

      await tester.tap(find.byKey(const Key('read-aloud-system-voice')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['voice null']);
    });

    testWidgets('sin voces instaladas, lo dice y queda la del sistema', (
      tester,
    ) async {
      await pump(tester, initial: _reading);
      await tester.tap(find.byKey(const Key('read-aloud-voice')));
      await tester.pumpAndSettle();

      expect(find.text(es.readAloudNoVoices), findsOneWidget);
      expect(find.byKey(const Key('read-aloud-system-voice')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });
}
