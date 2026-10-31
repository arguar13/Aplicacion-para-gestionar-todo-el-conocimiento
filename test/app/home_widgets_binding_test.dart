import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/home_widgets_binding.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/audio/audio_focus.dart';
import 'package:sinapsis/core/audio/media_session.dart';
import 'package:sinapsis/core/audio/media_session_hub.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../support/fake_home_screen_widgets.dart';
import '../support/library_harness.dart';

/// Los widgets de la pantalla de inicio enchufados a la app (F47, paso 7):
/// lo que se les cuenta y adónde lleva tocarlos, con la plataforma
/// reemplazada por un doble.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 9, 11, 10);
  late FakeHomeScreenWidgets widgets;
  late LibraryHarness harness;
  late String itemId;

  Future<void> setUpWith({bool supported = true}) async {
    widgets = FakeHomeScreenWidgets(supported: supported);
    harness = await LibraryHarness.create(
      extraOverrides: [
        clockProvider.overrideWithValue(() => now),
        homeScreenWidgetsProvider.overrideWithValue(widgets),
      ],
    );
    await harness.capture('Una fuente\n\nCon un texto largo para señalar.');
    itemId =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single
            .id;
  }

  tearDown(() async => widgets.openController.close());

  Future<void> addCard(String front) async {
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(itemId: itemId, front: front, back: 'R');
  }

  /// La app como la arma `App`: el router y los widgets por encima.
  Future<void> pumpApp(WidgetTester tester, {bool unlocked = true}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (unlocked) {
      harness.container
          .read(vaultSessionControllerProvider.notifier)
          .markUnlocked();
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(goRouterProvider);
            return HomeWidgetsBinding(
              router: router,
              child: MaterialApp.router(
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lo que se ve arriba de todo, también si se abrió encima (`push`).
  Uri location() => harness.container.read(goRouterProvider).state.uri;

  group('«Para hoy»', () {
    testWidgets('le cuenta las tarjetas de hoy, con el fin del día de '
        'estudio, y vuelve a contar cuando cambian', (tester) async {
      await setUpWith();
      await addCard('¿Uno?');
      await addCard('¿Dos?');
      await pumpApp(tester);

      final until = const StudyDay().endOf(now);
      expect(widgets.dueToday.last, DueToday(count: 2, validUntil: until));

      await addCard('¿Tres?');
      await tester.pumpAndSettle();
      expect(widgets.dueToday.last, DueToday(count: 3, validUntil: until));
    });

    testWidgets('con la bóveda cerrada no cuenta: el widget sigue con lo '
        'último', (tester) async {
      await setUpWith();
      await addCard('¿Uno?');
      await pumpApp(tester, unlocked: false);

      expect(widgets.dueToday, isEmpty);
    });
  });

  group('«Seguir escuchando»', () {
    testWidgets('lo que se escuchó llega al widget', (tester) async {
      await setUpWith();
      await pumpApp(tester);
      expect(widgets.continueListening, [null]);

      await harness.container
          .read(continueListeningProvider.notifier)
          .listened(
            title: 'El Imperio',
            location: RoutePaths.itemDetail(itemId),
          );
      await tester.pumpAndSettle();

      expect(
        widgets.continueListening.last,
        ContinueListening(
          title: 'El Imperio',
          location: RoutePaths.itemDetail(itemId),
        ),
      );
    });

    group('se alimenta de lo que suena con el foco de audio', () {
      /// Abre el elemento encima de la Biblioteca, como lo abre tocar una
      /// fila, y registra [source] en la tarjeta con su testigo [owner].
      Future<void> openAndRegister(
        WidgetTester tester,
        Object owner,
        _Source source,
      ) async {
        unawaited(
          harness.container
              .read(goRouterProvider)
              .push<void>(RoutePaths.itemDetail(itemId)),
        );
        await tester.pumpAndSettle();
        harness.container
            .read(mediaSessionSourcesProvider.notifier)
            .register(owner, source);
        await tester.pumpAndSettle();
      }

      testWidgets('lo que empieza a sonar llega a «Seguir escuchando», con la '
          'pantalla de arriba de todo', (tester) async {
        await setUpWith();
        await pumpApp(tester);
        final owner = Object();
        final source = _Source();
        addTearDown(source.dispose);
        await openAndRegister(tester, owner, source);

        harness.container.read(audioFocusProvider.notifier).claim(owner);
        source.sound('Un audio');
        await tester.pumpAndSettle();

        final expected = ContinueListening(
          title: 'Un audio',
          location: RoutePaths.itemDetail(itemId),
        );
        expect(harness.container.read(continueListeningProvider), expected);
        expect(widgets.continueListening.last, expected);
      });

      testWidgets('quieto, o sin el foco, no cuenta', (tester) async {
        await setUpWith();
        await pumpApp(tester);
        final owner = Object();
        final source = _Source();
        addTearDown(source.dispose);
        await openAndRegister(tester, owner, source);

        // Suena, pero el foco es de otro.
        source.sound('Sin el foco');
        await tester.pumpAndSettle();
        expect(harness.container.read(continueListeningProvider), isNull);

        // Con el foco, pero en pausa: abierto no es escuchado.
        source.sound('En pausa', playing: false);
        harness.container.read(audioFocusProvider.notifier).claim(owner);
        await tester.pumpAndSettle();
        expect(harness.container.read(continueListeningProvider), isNull);
      });

      testWidgets(
        'otro título de lo mismo que suena —el lector que pasa a otro '
        'texto— cuenta otra vez, desde la pantalla de ahora',
        (tester) async {
          await setUpWith();
          await pumpApp(tester);
          final owner = Object();
          final source = _Source();
          addTearDown(source.dispose);
          await openAndRegister(tester, owner, source);
          harness.container.read(audioFocusProvider.notifier).claim(owner);
          source.sound('Primero');
          await tester.pumpAndSettle();

          harness.container.read(goRouterProvider).go(RoutePaths.review);
          await tester.pumpAndSettle();
          // Pausar y seguir con lo mismo no cambia nada.
          source
            ..sound('Primero', playing: false)
            ..sound('Primero');
          await tester.pumpAndSettle();
          expect(
            harness.container.read(continueListeningProvider)?.location,
            RoutePaths.itemDetail(itemId),
          );

          source.sound('Segundo');
          await tester.pumpAndSettle();
          expect(
            harness.container.read(continueListeningProvider),
            const ContinueListening(
              title: 'Segundo',
              location: RoutePaths.review,
            ),
          );
        },
      );

      testWidgets('el foco pasa a otra fuente: cuenta la nueva', (
        tester,
      ) async {
        await setUpWith();
        await pumpApp(tester);
        final reader = Object();
        final audio = Object();
        final readerSource = _Source();
        final audioSource = _Source();
        addTearDown(readerSource.dispose);
        addTearDown(audioSource.dispose);
        await openAndRegister(tester, reader, readerSource);
        harness.container
            .read(mediaSessionSourcesProvider.notifier)
            .register(audio, audioSource);
        harness.container.read(audioFocusProvider.notifier).claim(reader);
        readerSource.sound('El texto');
        await tester.pumpAndSettle();

        audioSource.sound('El audio');
        harness.container.read(audioFocusProvider.notifier).claim(audio);
        await tester.pumpAndSettle();

        expect(
          harness.container.read(continueListeningProvider)?.title,
          'El audio',
        );
      });
    });
  });

  group('los toques', () {
    testWidgets('«Para hoy» lleva a Repasar', (tester) async {
      await setUpWith();
      await pumpApp(tester);

      widgets.tap(HomeWidgetKind.dueToday);
      await tester.pumpAndSettle();

      expect(location().path, RoutePaths.review);
    });

    testWidgets('«Guardar rápido» abre Guardar, listo para pegar o escribir', (
      tester,
    ) async {
      await setUpWith();
      await pumpApp(tester);

      widgets.tap(HomeWidgetKind.quickCapture);
      await tester.pumpAndSettle();

      expect(location().toString(), RoutePaths.quickCapture);
      expect(find.byType(CaptureScreen), findsOneWidget);
      final field = find.widgetWithText(TextField, es.captureTypePasteTextHint);
      expect(field, findsOneWidget);
      // Con el cursor ya en el cuadro.
      expect(
        tester.binding.focusManager.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>()
            ?.decoration
            ?.hintText,
        es.captureTypePasteTextHint,
      );
    });

    testWidgets('«Seguir escuchando» abre donde se escuchó', (tester) async {
      await setUpWith();
      await harness.container
          .read(continueListeningProvider.notifier)
          .listened(
            title: 'Una fuente',
            location: RoutePaths.itemDetail(itemId),
          );
      await pumpApp(tester);

      widgets.tap(HomeWidgetKind.continueListening);
      await tester.pumpAndSettle();

      expect(location().path, RoutePaths.itemDetail(itemId));
    });

    testWidgets('sin nada escuchado, «Seguir escuchando» solo abre la app', (
      tester,
    ) async {
      await setUpWith();
      await pumpApp(tester);
      final before = location();

      widgets.tap(HomeWidgetKind.continueListening);
      await tester.pumpAndSettle();

      expect(location(), before);
    });

    testWidgets('arrancando desde cero, con la bóveda cerrada, espera a que se '
        'abra y va una sola vez', (tester) async {
      await setUpWith();
      widgets.pendingOpen = HomeWidgetKind.dueToday;
      await pumpApp(tester, unlocked: false);
      expect(location().path, isNot(RoutePaths.review));

      harness.container
          .read(vaultSessionControllerProvider.notifier)
          .markUnlocked();
      await tester.pumpAndSettle();
      expect(location().path, RoutePaths.review);

      harness.container.read(goRouterProvider).go(RoutePaths.library);
      await tester.pumpAndSettle();
      expect(location().path, RoutePaths.library);
    });
  });

  testWidgets('donde no hay widgets no les cuenta nada ni los escucha', (
    tester,
  ) async {
    await setUpWith(supported: false);
    await addCard('¿Uno?');
    await pumpApp(tester);

    widgets.tap(HomeWidgetKind.dueToday);
    await tester.pumpAndSettle();

    expect(widgets.dueToday, isEmpty);
    expect(widgets.continueListening, isEmpty);
    expect(location().path, isNot(RoutePaths.review));
  });
}

/// Algo que suena en la tarjeta, de mentira: un audio, el lector.
class _Source implements MediaSessionSource {
  final _state = ValueNotifier<MediaSessionState?>(null);

  @override
  ValueListenable<MediaSessionState?> get state => _state;

  @override
  void handle(MediaCommand command) {}

  void sound(String title, {bool playing = true}) =>
      _state.value = MediaSessionState(title: title, playing: playing);

  void dispose() => _state.dispose();
}
