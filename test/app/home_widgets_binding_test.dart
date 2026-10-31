import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/home_widgets_binding.dart';
import 'package:sinapsis/app/router/app_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
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

    testWidgets('hasta el reproductor anclado, lo alimenta el lector en voz '
        'alta, con la pantalla desde donde se escucha', (tester) async {
      await setUpWith();
      await pumpApp(tester);
      // Abierto encima de la Biblioteca, como lo abre tocar una fila.
      unawaited(
        harness.container
            .read(goRouterProvider)
            .push<void>(RoutePaths.itemDetail(itemId)),
      );
      await tester.pumpAndSettle();

      await harness.container
          .read(readAloudControllerProvider.notifier)
          .open(
            const ReadableDocument(
              id: 'item:uno',
              title: 'Una fuente',
              segments: [
                ReadableSegment(
                  sourceKey: 'texto',
                  start: 0,
                  end: 5,
                  spoken: 'Hola.',
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();

      expect(
        harness.container.read(continueListeningProvider),
        ContinueListening(
          title: 'Una fuente',
          location: RoutePaths.itemDetail(itemId),
        ),
      );
      expect(widgets.continueListening.last?.title, 'Una fuente');
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
