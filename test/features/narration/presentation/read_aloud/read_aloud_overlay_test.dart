import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/reading_queue.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_clearance.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_player_extent.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_text_to_speech_service.dart';

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
  Future<void> open(
    ReadableDocument document, {
    int? fromSegment,
    ReadScope? scope,
  }) async {
    calls.add('open ${document.id}');
    state = state.copyWith(
      document: document,
      scope: scope ?? document.defaultScope,
      panel: ReadAloudPanel.expanded,
      playing: true,
    );
  }

  @override
  Future<void> setScope(ReadScope scope) async {
    calls.add('scope ${scope.name}');
    state = state.copyWith(scope: scope, segmentIndex: 0, playing: true);
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
  Future<void> seekTo(Duration time) async =>
      calls.add('seek ${time.inSeconds}');

  @override
  void cycleRepeat() {
    calls.add('repeat');
    state = state.copyWith(
      queue: state.queue.withRepeat(state.queue.repeat.next),
    );
  }

  @override
  Future<void> enqueue(ReadableDocument document, {ReadScope? scope}) async {
    calls.add('enqueue ${document.id}');
    state = state.copyWith(queue: state.queue.add(QueuedReading(document)));
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
  final collapsed = find.byKey(const Key('read-aloud-collapsed'));

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
    Map<String, Object> stored = const {},
  }) async {
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    reader = _FakeReadAloud(initial);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(
          FakeTextToSpeechService(voices: voices),
        ),
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
      expect(
        find.text(es.f47P2ReadingWith(es.f47P2PhoneVoice, '1,0×')),
        findsOneWidget,
      );
      // Leyendo, el botón se fue: lo que suena se maneja desde el
      // reproductor.
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

    testWidgets('leyendo no aparece, aunque la pantalla tenga texto: lo que '
        'suena está en el reproductor achicado', (tester) async {
      await pump(
        tester,
        offered: _document,
        initial: _reading.copyWith(panel: ReadAloudPanel.minimized),
      );

      expect(button, findsNothing);
      expect(collapsed, findsOneWidget);
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

  group('el reproductor anclado (F47, paso 2)', () {
    /// Diez oraciones de diez palabras: 40 s a 1×.
    final long = ReadableDocument(
      id: 'largo',
      title: 'Un texto largo',
      segments: buildReadableSegments(
        [
          for (var s = 0; s < 10; s++)
            '${[for (var w = 0; w < 10; w++) 'p$s$w'].join(' ')}.',
        ].join('\n'),
        sourceKey: 'largo',
      ),
    );

    testWidgets('pausa, reproduce, salta 10 s para los dos lados', (
      tester,
    ) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-play')));
      await tester.pumpAndSettle();
      expect(
        find.text(es.f47P2PausedWith(es.f47P2PhoneVoice, '1,0×')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('read-aloud-play')));
      await tester.tap(find.byKey(const Key('read-aloud-replay')));
      await tester.tap(find.byKey(const Key('read-aloud-forward')));

      expect(reader.calls, ['pause', 'play', 'skip -10', 'skip 10']);
    });

    testWidgets('el tiempo leído y el total, y la barra que se arrastra', (
      tester,
    ) async {
      await pump(
        tester,
        initial: ReadAloudState(
          document: long,
          segmentIndex: 5,
          playing: true,
          panel: ReadAloudPanel.expanded,
        ),
      );

      expect(find.text('0:20'), findsOneWidget);
      expect(find.text('0:40'), findsOneWidget);
      final bar = tester.widget<Slider>(
        find.byKey(const Key('read-aloud-progress')),
      );
      expect(bar.value, 0.5);

      // Soltarla al final de la barra va a ese tiempo.
      await tester.drag(
        find.byKey(const Key('read-aloud-progress')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle();
      expect(reader.calls, ['seek 40']);
    });

    testWidgets('achicar lo deja en una línea con ▶, el título, +10 s y ⌃', (
      tester,
    ) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-minimize')));
      await tester.pumpAndSettle();
      expect(reader.calls, ['minimize']);
      expect(player, findsNothing);
      expect(collapsed, findsOneWidget);
      expect(find.text(_document.title), findsOneWidget);

      await tester.tap(find.byKey(const Key('read-aloud-collapsed-forward')));
      await tester.tap(find.byKey(const Key('read-aloud-collapsed-play')));
      await tester.pumpAndSettle();
      expect(reader.calls, ['minimize', 'skip 10', 'pause']);

      await tester.tap(find.byKey(const Key('read-aloud-expand')));
      await tester.pumpAndSettle();
      expect(reader.calls.last, 'expand');
      expect(player, findsOneWidget);
    });

    testWidgets('achicado, tocar el título lo abre', (tester) async {
      await pump(
        tester,
        initial: _reading.copyWith(panel: ReadAloudPanel.minimized),
      );

      await tester.tap(find.text(_document.title));
      await tester.pumpAndSettle();

      expect(reader.calls, ['expand']);
    });

    testWidgets('achicado, arrastrarlo hacia abajo deja de leer', (
      tester,
    ) async {
      await pump(
        tester,
        initial: _reading.copyWith(panel: ReadAloudPanel.minimized),
      );

      await tester.fling(collapsed, const Offset(0, 120), 800);
      await tester.pumpAndSettle();

      expect(reader.calls, ['close']);
      expect(collapsed, findsNothing);
    });

    testWidgets('«Dejar de leer», en la cola', (tester) async {
      await pump(tester, initial: _reading);

      await tester.tap(find.byKey(const Key('read-aloud-queue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('read-aloud-close')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['close']);
      expect(player, findsNothing);
      expect(button, findsNothing);
    });

    testWidgets('⟲ pasa por no repetir, la cola y esto', (tester) async {
      await pump(tester, initial: _reading);
      final repeat = find.byKey(const Key('read-aloud-repeat'));

      expect(tester.widget<IconButton>(repeat).tooltip, es.f47P2RepeatOff);
      await tester.tap(repeat);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(repeat).tooltip, es.f47P2RepeatAll);
      await tester.tap(repeat);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(repeat).tooltip, es.f47P2RepeatOne);
      expect(reader.state.queue.repeat, ReadAloudRepeat.one);
    });

    testWidgets('la cola suma lo de la pantalla y lo cuenta en ☰', (
      tester,
    ) async {
      const other = ReadableDocument(
        id: 'otro',
        title: 'Otro texto',
        segments: [
          ReadableSegment(sourceKey: 'o', start: 0, end: 4, spoken: 'Otro'),
        ],
      );
      await pump(tester, initial: _reading, offered: other);

      await tester.tap(find.byKey(const Key('read-aloud-queue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-aloud-queue-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('read-aloud-queue-add')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['enqueue otro']);
      expect(find.byKey(const Key('read-aloud-queued-0')), findsOneWidget);

      Navigator.of(tester.element(find.byType(ListTile).first)).pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('read-aloud-queue')))
            .tooltip,
        es.f47P2QueueCount(1),
      );
    });

    testWidgets('si el motor de voz falla, lo dice', (tester) async {
      await pump(
        tester,
        initial: _reading.copyWith(playing: false, failed: true),
      );

      expect(find.text(es.readAloudFailed), findsOneWidget);
    });

    testWidgets('queda encima de la barra de navegación y a lo ancho, y '
        'abajo del todo sin barra', (tester) async {
      final router = await pump(tester, initial: _reading, withBar: true);

      expect(tester.getRect(player).bottom, _phone.height - 80);
      expect(tester.getRect(player).width, _phone.width);

      unawaited(router.push('/arriba'));
      await tester.pumpAndSettle();
      expect(tester.getRect(player).bottom, _phone.height);
    });

    testWidgets('se para encima de lo que pide esquivar', (tester) async {
      await pump(
        tester,
        initial: _reading,
        screen: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ReadAloudClearance(child: SizedBox(height: 100)),
          ),
        ),
      );

      expect(tester.getRect(player).bottom, _phone.height - 100);
    });

    testWidgets('publica cuánto ocupa, y los avisos van por encima de él', (
      tester,
    ) async {
      final router = await pump(tester, initial: _reading, withBar: true);
      final extent = container.read(readAloudPlayerExtentProvider);
      final top = tester.getRect(player).top;
      expect(extent.current, _phone.height - top);
      expect(extent.resting, extent.current);

      final context = router.routerDelegate.navigatorKey.currentContext!;
      ScaffoldMessenger.of(context).showSnackBar(
        // Como los de la app: flotantes, por el tema.
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Un aviso'),
        ),
      );
      await tester.pumpAndSettle();

      // El aviso mismo, sin su margen.
      final snack = tester.getRect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Material),
        ),
      );
      expect(snack.bottom, lessThanOrEqualTo(top));

      await reader.close();
      await tester.pumpAndSettle();
      expect(
        container.read(readAloudPlayerExtentProvider),
        const PlayerExtent(),
      );
    });

    testWidgets('con la Lectura enfocada, se achica mientras te desplazás y '
        'vuelve al soltar', (tester) async {
      await pump(
        tester,
        initial: _reading,
        stored: {'narration_focused_reading': true},
        screen: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++) ListTile(title: Text('Fila $i')),
            ],
          ),
        ),
      );
      expect(player, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Fila 2')),
      );
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await tester.pump();
      expect(player, findsNothing);
      expect(collapsed, findsOneWidget);
      // Es solo lo que se ve: lo elegido sigue siendo abierto, y los avisos
      // no se mueven mientras tanto.
      expect(reader.state.panel, ReadAloudPanel.expanded);
      final extent = container.read(readAloudPlayerExtentProvider);
      expect(extent.current, lessThan(extent.resting));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(player, findsOneWidget);
    });

    testWidgets('sin la Lectura enfocada, desplazarse no lo cambia', (
      tester,
    ) async {
      await pump(
        tester,
        initial: _reading,
        screen: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++) ListTile(title: Text('Fila $i')),
            ],
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Fila 2')),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      expect(player, findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('«Leer: Todo · Resumen · Síntesis · Palabras clave» (F39)', () {
    const piece = ReadableSegment(
      sourceKey: 'texto',
      start: 0,
      end: 4,
      spoken: 'Algo',
    );
    const studied = ReadableDocument(
      id: 'item-2',
      title: 'Un texto estudiado',
      segments: [piece],
      scopes: {
        ReadScope.summary: [piece],
        ReadScope.synthesis: [],
        ReadScope.keywords: [piece],
      },
    );
    const readingStudied = ReadAloudState(
      document: studied,
      playing: true,
      panel: ReadAloudPanel.expanded,
    );

    Finder chip(ReadScope scope) =>
        find.byKey(Key('read-aloud-scope-${scope.name}'));

    /// Las partes están en la cola (F47, paso 2).
    Future<void> openQueue(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('read-aloud-queue')));
      await tester.pumpAndSettle();
    }

    bool enabled(WidgetTester tester, ReadScope scope) =>
        tester.widget<ChoiceChip>(chip(scope)).onSelected != null;

    testWidgets('un texto que no se estudia no lleva la fila', (tester) async {
      await pump(tester, initial: _reading);
      await openQueue(tester);

      expect(find.byKey(const Key('read-aloud-scopes')), findsNothing);
      expect(find.text(es.readAloudScopeLabel), findsNothing);
    });

    testWidgets('un texto estudiado ofrece las cuatro, con la que se lee '
        'elegida', (tester) async {
      await pump(tester, initial: readingStudied);
      await openQueue(tester);

      expect(find.text(es.readAloudScopeLabel), findsOneWidget);
      expect(find.text(es.readAloudScopeAll), findsOneWidget);
      expect(find.text(es.readAloudScopeSummary), findsOneWidget);
      expect(find.text(es.readAloudScopeSynthesis), findsOneWidget);
      expect(find.text(es.readAloudScopeKeywords), findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip(ReadScope.all)).selected, isTrue);
      expect(
        tester.widget<ChoiceChip>(chip(ReadScope.summary)).selected,
        isFalse,
      );
    });

    testWidgets('las que no tienen datos aparecen apagadas', (tester) async {
      await pump(tester, initial: readingStudied);
      await openQueue(tester);

      expect(enabled(tester, ReadScope.all), isTrue);
      expect(enabled(tester, ReadScope.summary), isTrue);
      expect(enabled(tester, ReadScope.synthesis), isFalse);
      expect(enabled(tester, ReadScope.keywords), isTrue);

      await tester.tap(chip(ReadScope.synthesis));
      await tester.pumpAndSettle();
      expect(reader.calls, isEmpty);
    });

    testWidgets('con el texto plegado, «Todo» queda apagado', (tester) async {
      await pump(
        tester,
        initial: ReadAloudState(
          document: ReadableDocument(
            id: studied.id,
            title: studied.title,
            segments: const [],
            scopes: studied.scopes,
          ),
          scope: ReadScope.summary,
          playing: true,
          panel: ReadAloudPanel.expanded,
        ),
      );
      await openQueue(tester);

      expect(enabled(tester, ReadScope.all), isFalse);
      expect(
        tester.widget<ChoiceChip>(chip(ReadScope.summary)).selected,
        isTrue,
      );
    });

    testWidgets('elegir una parte se la pide al lector', (tester) async {
      await pump(tester, initial: readingStudied);
      await openQueue(tester);

      await tester.tap(chip(ReadScope.keywords));
      await tester.pumpAndSettle();

      expect(reader.calls, ['scope keywords']);
      expect(
        tester.widget<ChoiceChip>(chip(ReadScope.keywords)).selected,
        isTrue,
      );
    });

    testWidgets('con su propio audio, «Todo» se puede elegir y lee la '
        'transcripción (F40)', (tester) async {
      await pump(
        tester,
        initial: ReadAloudState(
          document: studied.withOwnAudio(),
          scope: ReadScope.summary,
          playing: true,
          panel: ReadAloudPanel.expanded,
        ),
      );
      await openQueue(tester);

      expect(enabled(tester, ReadScope.all), isTrue);
      await tester.tap(chip(ReadScope.all));
      await tester.pumpAndSettle();

      expect(reader.calls, ['scope all']);
    });

    testWidgets('tocar el botón redondo de un texto estudiado con su propio '
        'audio empieza por lo estudiado', (tester) async {
      await pump(tester, offered: studied.withOwnAudio());

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(reader.calls, ['open item-2']);
      expect(reader.state.scope, ReadScope.summary);
    });
  });

  group('la velocidad (F47, paso 2, decisión H)', () {
    testWidgets('la regla de 0,5× a 3×, con los atajos sin candados', (
      tester,
    ) async {
      await pump(tester, initial: _reading);
      expect(find.text('1,0×'), findsOneWidget);

      await tester.tap(find.byKey(const Key('read-aloud-speed')));
      await tester.pumpAndSettle();
      // Con el panel abierto, el reproductor se hace a un lado.
      expect(player, findsNothing);

      for (final preset in ['1.0', '1.2', '1.5', '2.0', '3.0']) {
        expect(find.byKey(Key('read-aloud-speed-$preset')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('read-aloud-speed-1.5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('read-aloud-speed-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('read-aloud-speed-3.0')));
      await tester.pumpAndSettle();

      expect(reader.calls, ['speed 1.50', 'speed 1.60', 'speed 3.00']);
      expect(find.text('3,0×'), findsWidgets);
      final up = tester.widget<IconButton>(
        find.byKey(const Key('read-aloud-speed-up')),
      );
      expect(up.onPressed, isNull);
    });

    testWidgets('arrastrar la regla cambia la velocidad al soltar, de a una '
        'décima', (tester) async {
      await pump(tester, initial: _reading);
      await tester.tap(find.byKey(const Key('read-aloud-speed')));
      await tester.pumpAndSettle();

      // 14 píxeles por décima: hacia la izquierda, más rápido.
      final ruler = find.byKey(const Key('read-aloud-speed-ruler'));
      final gesture = await tester.startGesture(tester.getCenter(ruler));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('read-aloud-speed-value')))
            .data,
        '1,5×',
      );
      expect(reader.calls, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reader.calls, ['speed 1.50']);
    });

    testWidgets('el lector de pantalla la sube y la baja de a una décima', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, initial: _reading);
      await tester.tap(find.byKey(const Key('read-aloud-speed')));
      await tester.pumpAndSettle();

      final ruler = find.byKey(const Key('read-aloud-speed-ruler'));
      expect(
        tester.getSemantics(ruler),
        matchesSemantics(
          label: es.f47P2SpeedRuler,
          value: '1,0×',
          increasedValue: '1,1×',
          decreasedValue: '0,9×',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
          isSlider: true,
        ),
      );
      tester.semantics.increase(find.semantics.byLabel(es.f47P2SpeedRuler));
      await tester.pumpAndSettle();

      expect(reader.calls, ['speed 1.10']);
      semantics.dispose();
    });
  });

  group('la voz (F47, paso 3)', () {
    const argentina = NarrationVoice(
      name: 'es-ar-x-ara-local',
      locale: 'es-AR',
    );
    const daniela = NarrationVoice(
      name: 'vits-piper-es_AR-daniela-high#0',
      locale: 'es-AR',
      engine: NarrationEngine.offline,
    );

    VoiceFace faceShown(WidgetTester tester) => tester
        .widget<VoiceFaceView>(
          find.descendant(
            of: find.byKey(const Key('read-aloud-voice')),
            matching: find.byType(VoiceFaceView),
          ),
        )
        .face;

    testWidgets('la cara del reproductor es la de la voz que lee, y dice su '
        'nombre (pasos 2 y 3)', (tester) async {
      await pump(tester, initial: _reading.copyWith(voice: daniela));

      final profile = voiceProfileOf(daniela)!;
      expect(faceShown(tester), VoiceFace.of(profile.id, profile.label));
      expect(
        find.text(es.f47P2ReadingWith(profile.name!, '1,0×')),
        findsOneWidget,
      );
    });

    testWidgets('con la voz del sistema, su propia cara', (tester) async {
      await pump(tester, initial: _reading);

      expect(
        faceShown(tester),
        VoiceFace.of(ReadAloudVoiceFace.systemFaceId, es.readAloudSystemVoice),
      );
    });

    testWidgets('abre la biblioteca de voces, y elegir una la usa para leer', (
      tester,
    ) async {
      await pump(tester, initial: _reading, voices: const [argentina]);
      await tester.tap(find.byKey(const Key('read-aloud-voice')));
      await tester.pumpAndSettle();

      expect(find.text(es.f47P3LibraryTitle), findsOneWidget);
      // Con el panel abierto, el reproductor se hace a un lado.
      expect(player, findsNothing);

      final argentinaCard = find.textContaining(es.readAloudVoiceNumber(1));
      await tester.ensureVisible(argentinaCard);
      await tester.pumpAndSettle();
      await tester.tap(argentinaCard);
      await tester.pumpAndSettle();
      expect(reader.calls, ['voice es-ar-x-ara-local']);
    });

    testWidgets('elegir la voz del sistema vuelve a la del teléfono', (
      tester,
    ) async {
      await pump(tester, initial: _reading.copyWith(voice: argentina));
      await tester.tap(find.byKey(const Key('read-aloud-voice')));
      await tester.pumpAndSettle();

      final system = find.byKey(const Key('read-aloud-system-voice'));
      await tester.ensureVisible(system);
      await tester.pumpAndSettle();
      await tester.tap(system);
      await tester.pumpAndSettle();

      expect(reader.calls, ['voice null']);
    });
  });
}
