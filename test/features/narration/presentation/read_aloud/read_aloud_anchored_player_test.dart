import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/sleep_timer.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_anchored_player.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_text_to_speech_service.dart';

/// El reproductor anclado de verdad (F47, paso 2) —el lector con un motor de
/// voz de mentira— en un teléfono de 360 de ancho con la letra al doble, en
/// claro y en oscuro, con el lector de pantalla y sin animaciones.
void main() {
  final es = AppLocalizationsEs();

  /// Diez oraciones de diez palabras: 40 s a 1×, con un título largo, que
  /// no entra.
  final document = ReadableDocument(
    id: 'largo',
    title: 'Las ideas de Ada Lovelace sobre la máquina analítica de Babbage',
    segments: buildReadableSegments(
      [
        for (var s = 0; s < 10; s++)
          '${[for (var w = 0; w < 10; w++) 'p$s$w'].join(' ')}.',
      ].join('\n'),
      sourceKey: 'largo',
    ),
    scopes: {
      ReadScope.summary: buildReadableSegments('p00 p01.', sourceKey: 'largo'),
    },
  );
  final other = ReadableDocument(
    id: 'otro',
    title: 'Otro documento para escuchar después, también con título largo',
    segments: buildReadableSegments('Otra cosa.', sourceKey: 'otro'),
  );

  late ProviderContainer container;

  ReadAloudController controller() =>
      container.read(readAloudControllerProvider.notifier);
  ReadAloudState state() => container.read(readAloudControllerProvider);

  Future<void> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool still = true,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    }
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        textToSpeechServiceProvider.overrideWithValue(
          FakeTextToSpeechService(),
        ),
        narrationClockProvider.overrideWithValue(() => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    container.read(readableRegistryProvider.notifier).offer(Object(), other);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Pantalla')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ReadAloudOverlay(router: router, child: child!),
        ),
      ),
    );
    await controller().open(document, fromSegment: 5);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    group('a 360 dp con la letra al doble, en ${brightness.name}', () {
      testWidgets('abierto, entra entero y el lector de pantalla dice cada '
          'control', (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, brightness: brightness);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('read-aloud-player')), findsOneWidget);
        // Los botones de íconos se dicen por su ayuda.
        for (final (key, tooltip) in [
          ('read-aloud-play', es.mediaPlayerPause),
          ('read-aloud-replay', es.readAloudReplay),
          ('read-aloud-forward', es.readAloudForward),
          ('read-aloud-minimize', es.f47P2Collapse),
          ('read-aloud-repeat', es.f47P2RepeatOff),
          ('read-aloud-queue', es.f47P2QueueCount(0)),
        ]) {
          expect(
            tester.getSemantics(find.byKey(Key(key))).tooltip,
            tooltip,
            reason: key,
          );
        }
        expect(
          tester
              .getSemantics(find.byKey(const Key('read-aloud-voice')))
              .tooltip,
          es.f47P2VoiceFace(es.f47P2PhoneVoice),
        );
        expect(
          find.bySemanticsLabel(es.f47P2SpeedButton('1,0×')),
          findsOneWidget,
        );
        // La barra dice el tiempo leído y el total.
        expect(
          find.semantics.byValue(es.f47P2TimeOf('0:20', '0:40')),
          findsOne,
        );
        semantics.dispose();
      });

      testWidgets('achicado, entra en una línea y se puede dejar de leer '
          'desde el lector de pantalla', (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, brightness: brightness);
        controller().minimize();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final collapsed = find.byKey(const Key('read-aloud-collapsed'));
        expect(collapsed, findsOneWidget);
        expect(
          tester
              .getSemantics(find.byKey(const Key('read-aloud-expand')))
              .tooltip,
          es.f47P2Expand,
        );

        final data = tester.getSemantics(collapsed).getSemanticsData();
        expect(data.customSemanticsActionIds, isNotEmpty);
        semantics.dispose();
      });

      testWidgets('la cola entra entera, con su parte, lo de la pantalla, '
          'repetir y el temporizador', (tester) async {
        await pump(tester, brightness: brightness);

        await tester.tap(find.byKey(const Key('read-aloud-queue')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(es.f47P2NowPlaying), findsOneWidget);
        expect(find.byKey(const Key('read-aloud-scopes')), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('read-aloud-queue-add')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('read-aloud-queue-add')));
        await tester.pumpAndSettle();
        expect(state().queue.upcoming.single.document.id, 'otro');
        // Ya en la cola, lo de la pantalla no se ofrece dos veces.
        expect(find.byKey(const Key('read-aloud-queued-0')), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('read-aloud-repeat-all')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('read-aloud-repeat-all')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('read-aloud-sleep-minutes30')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('read-aloud-sleep-minutes30')));
        await tester.pumpAndSettle();
        expect(find.text(es.f47P2SleepLeft(30)), findsOneWidget);
        expect(state().sleep?.choice, SleepTimerChoice.minutes30);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(
          find.byKey(const Key('read-aloud-sleep-endOfReading')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('read-aloud-sleep-endOfReading')),
        );
        await tester.pumpAndSettle();
        expect(find.text(es.f47P2SleepAtEnd), findsOneWidget);

        controller().setSleepTimer(null);
        await tester.pumpAndSettle();
      });

      testWidgets('la cola: tocar uno lo lee, ✕ lo saca, y «Limpiar cola»', (
        tester,
      ) async {
        await pump(tester, brightness: brightness);
        final third = ReadableDocument(
          id: 'tercero',
          title: 'Tercero',
          segments: buildReadableSegments('Lo tercero.', sourceKey: 't'),
        );
        await controller().enqueue(other);
        await controller().enqueue(third);
        await tester.tap(find.byKey(const Key('read-aloud-queue')));
        await tester.pumpAndSettle();

        // A 360 con la letra al doble, la cola queda abajo en la hoja: se
        // desplaza hasta ella, y la lista se arma a medida que se ve.
        final sheet = find.byKey(const Key('read-aloud-queue-sheet'));
        Future<void> reach(Finder target) async {
          await tester.dragUntilVisible(target, sheet, const Offset(0, -150));
          await tester.pumpAndSettle();
        }

        await reach(find.byKey(const Key('read-aloud-queue-remove-0')));
        await tester.tap(find.byKey(const Key('read-aloud-queue-remove-0')));
        await tester.pumpAndSettle();
        expect(state().queue.upcoming.single.document.id, 'tercero');

        await tester.dragUntilVisible(
          find.text('Tercero'),
          sheet,
          const Offset(0, 150),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tercero'));
        await tester.pumpAndSettle();
        expect(state().document?.id, 'tercero');
        expect(state().queue.isEmpty, isTrue);

        await controller().enqueue(other);
        await tester.pumpAndSettle();
        await reach(find.byKey(const Key('read-aloud-queue-clear')));
        await tester.tap(find.byKey(const Key('read-aloud-queue-clear')));
        await tester.pumpAndSettle();
        expect(state().queue.isEmpty, isTrue);
        expect(find.byKey(const Key('read-aloud-queue-empty')), findsOneWidget);
      });

      testWidgets('la velocidad entra entera', (tester) async {
        await pump(tester, brightness: brightness);

        await tester.tap(find.byKey(const Key('read-aloud-speed')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('read-aloud-speed-ruler')), findsOneWidget);
        expect(find.byKey(const Key('read-aloud-speed-3.0')), findsOneWidget);
      });
    });
  }

  group('el título que no entra', () {
    testWidgets('sin animaciones, no se mueve: queda con sus tres puntos', (
      tester,
    ) async {
      await pump(tester);

      expect(tester.hasRunningAnimations, isFalse);
      final title = tester.widget<Text>(find.text(document.title));
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('con animaciones, se desliza dos veces y vuelve a quedarse '
        'quieto', (tester) async {
      await pump(tester, still: false);
      controller().minimize();
      await tester.pump();
      // Un cuadro para que arranque, y después a mitad de la pasada.
      await tester.pump();
      await tester.pump(MarqueeText.pause + const Duration(milliseconds: 500));

      // A mitad de la pasada, el texto se corrió a la izquierda.
      expect(tester.hasRunningAnimations, isTrue);
      final moving = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text(document.title),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(moving.transform.getTranslation().x, lessThan(0));

      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        tester.widget<Text>(find.text(document.title)).overflow,
        TextOverflow.ellipsis,
      );
    });
  });
}
