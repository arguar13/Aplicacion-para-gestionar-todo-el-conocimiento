import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_overlay.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';
import '../../../../support/read_aloud_test_support.dart';

/// Lo que venía sonando antes de entrar a Repasar: un documento abierto en
/// otra pantalla.
const _document = ReadableDocument(
  id: 'item-1',
  title: 'Las ideas de Ada Lovelace',
  segments: [
    ReadableSegment(
      sourceKey: 'texto',
      start: 0,
      end: 10,
      spoken: 'Una oración',
    ),
  ],
);

/// La pantalla de un documento, que se declara para leer: de acá se va a
/// Repasar con el lector sonando.
class _DocumentScreen extends StatelessWidget {
  const _DocumentScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: ReadableRegion(document: _document, child: Text('Un documento')),
  );
}

/// Repasar sin el lector en voz alta (F47, mejora 20): la tarjeta no se
/// declara texto para leer —en ninguna de sus formas, ni con la respuesta a
/// la vista—, así que el botón redondo no aparece; lo que venía sonando de
/// otra pantalla sigue, como al cambiar de pestaña.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  final button = find.byKey(const Key('read-aloud-button'));
  final player = find.byKey(const Key('read-aloud-player'));

  setUp(() async {
    harness = await LibraryHarness.create(
      extraOverrides: [
        readAloudControllerProvider.overrideWith(FakeReadAloudController.new),
      ],
    );
  });

  ReadableDocument? offered() =>
      harness.container.read(currentReadableProvider);

  FakeReadAloudController reader() =>
      harness.container.read(readAloudControllerProvider.notifier)
          as FakeReadAloudController;

  /// El elemento del que salen las tarjetas.
  Future<String> seedItem() async {
    await harness.capture('Una fuente\n\nCon algo para repasar.');
    return (await harness.container
            .read(libraryRepositoryProvider)
            .list(const LibraryQuery()))
        .getRight()
        .toNullable()!
        .single
        .id;
  }

  Future<void> seedSimple() async {
    final itemId = await seedItem();
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(itemId: itemId, front: '¿Qué es?', back: 'Una respuesta.');
  }

  Future<void> seedMultipleChoice() async {
    final itemId = await seedItem();
    await harness.container
        .read(flashcardRepositoryProvider)
        .createMultipleChoice(
          itemId: itemId,
          front: '¿La capital?',
          options: const [
            FlashcardOptionDraft(content: 'Roma', isCorrect: true),
            FlashcardOptionDraft(content: 'Milán', isCorrect: false),
          ],
        );
  }

  Future<void> seedCloze() async {
    final itemId = await seedItem();
    await harness.container
        .read(flashcardRepositoryProvider)
        .create(
          itemId: itemId,
          front: 'El {{c1::Imperio}} cayó',
          back: '',
          kind: FlashcardKind.cloze,
          clozeIndex: 1,
        );
  }

  /// La app con el lector flotante encima, como en `App`, en un teléfono de
  /// 360 de ancho con la letra al doble, en [brightness]: la pantalla de un
  /// documento en `/` y Repasar en `/repasar`.
  Future<GoRouter> pump(
    WidgetTester tester, {
    String initialLocation = '/repasar',
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = const Size(360, 780)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, _) => const _DocumentScreen()),
        GoRoute(path: '/repasar', builder: (_, _) => const ReviewScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
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
    await tester.pumpAndSettle();
    return router;
  }

  /// Ni el botón ni nada ofrecido al lector, y nada que lo nombre para el
  /// lector de pantalla.
  void expectNoReader(WidgetTester tester) {
    expect(offered(), isNull);
    expect(button, findsNothing);
    expect(find.byTooltip(es.readAloudTooltip), findsNothing);
  }

  for (final brightness in Brightness.values) {
    group('en ${brightness.name}', () {
      testWidgets('una tarjeta simple no se ofrece al lector: ni la pregunta '
          'ni, revelada, la respuesta; «Explicar» sigue ahí', (tester) async {
        final semantics = tester.ensureSemantics();
        await seedSimple();
        await pump(tester, brightness: brightness);

        expect(find.text('¿Qué es?'), findsOneWidget);
        expectNoReader(tester);

        await tester.tap(find.byKey(const Key('review-show-answer')));
        await tester.pumpAndSettle();

        expect(find.text('Una respuesta.'), findsOneWidget);
        expectNoReader(tester);
        expect(find.byKey(const Key('review-explain')), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });

      testWidgets('una de opción múltiple tampoco, ni antes ni después de '
          'contestar', (tester) async {
        await seedMultipleChoice();
        await pump(tester, brightness: brightness);

        expect(find.text('¿La capital?'), findsOneWidget);
        expectNoReader(tester);

        await tester.tap(find.text('Roma'));
        await tester.pumpAndSettle();

        expectNoReader(tester);
        expect(find.byKey(const Key('review-explain')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('una de huecos tampoco, ni con el hueco resuelto', (
        tester,
      ) async {
        await seedCloze();
        await pump(tester, brightness: brightness);

        expect(find.byKey(const Key('review-cloze-question')), findsOneWidget);
        expectNoReader(tester);

        await tester.tap(find.byKey(const Key('review-show-answer')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('review-cloze-answer')), findsOneWidget);
        expectNoReader(tester);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('lo que venía sonando', () {
    testWidgets('sigue al entrar a Repasar, con su reproductor, hasta que la '
        'persona lo pare', (tester) async {
      await seedSimple();
      final router = await pump(tester, initialLocation: '/');
      // En el documento, el lector lo ofrece y empieza a leerlo.
      expect(offered()?.id, _document.id);
      reader().readAt(offered()!, 0);
      await tester.pumpAndSettle();
      expect(player, findsOneWidget);

      router.go('/repasar');
      await tester.pumpAndSettle();

      expect(find.text('¿Qué es?'), findsOneWidget);
      // Repasar no ofrece nada, y lo de antes sigue sonando, con el
      // reproductor a la vista.
      expect(offered(), isNull);
      final state = harness.container.read(readAloudControllerProvider);
      expect(state.document?.id, _document.id);
      expect(state.playing, isTrue);
      expect(state.panel, ReadAloudPanel.expanded);
      expect(player, findsOneWidget);

      // Revelar la tarjeta —con el espacio: el reproductor abierto tapa el
      // botón de abajo— no lo corta ni lo cambia.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Una respuesta.'), findsOneWidget);
      expect(offered(), isNull);
      expect(
        harness.container.read(readAloudControllerProvider).document?.id,
        _document.id,
      );
      expect(player, findsOneWidget);
    });

    testWidgets('minimizado, sigue el botón con su anillo: es lo que suena, '
        'no la tarjeta', (tester) async {
      await seedSimple();
      final router = await pump(tester, initialLocation: '/');
      reader()
        ..readAt(offered()!, 0)
        ..minimize();
      await tester.pumpAndSettle();

      router.go('/repasar');
      await tester.pumpAndSettle();

      expect(offered(), isNull);
      expect(button, findsOneWidget);
      expect(find.byKey(const Key('read-aloud-ring')), findsOneWidget);

      // Tocarlo abre lo que suena, no la tarjeta.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        harness.container.read(readAloudControllerProvider).document?.id,
        _document.id,
      );
      expect(player, findsOneWidget);
    });
  });
}
