import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_flip_card.dart';

import 'support/study_fakes.dart';
import 'support/study_viewer_harness.dart';

FlashcardDeck _deck({bool inReview = false, String? illustrationRef}) =>
    FlashcardDeck(
      title: 'Éxodo',
      inReview: inReview,
      illustrationFailure: illustrationRef != null
          ? ImageFailure.noBilling
          : null,
      illustrationAccount: illustrationRef != null ? 'Personal' : null,
      cards: [
        DeckCard(
          id: 'c1',
          front: '¿Quién guía al pueblo?',
          back: 'Moisés.',
          hint: 'Empieza con M.',
          documentId: 'doc',
          icon: 'history',
          illustrationRef: illustrationRef,
        ),
        const DeckCard(
          id: 'c2',
          front: '¿Qué se abre?',
          back: 'El mar.',
          documentId: 'doc',
        ),
        const DeckCard(
          id: 'c3',
          front: '¿Adónde llegan?',
          back: 'Al Sinaí.',
          documentId: 'doc',
        ),
      ],
    );

/// Espera a que el interruptor termine de guardar, sin `pumpAndSettle`: la
/// rueda de «guardando» no se queda quieta para siempre si algo falla.
Future<void> settleSaving(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    // Escribir en la base de la prueba avanza con el reloj de verdad.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
    final tile = tester.widget<SwitchListTile>(
      find.byKey(const Key('deck-in-review')),
    );
    if (tile.onChanged != null) break;
  }
  await tester.pumpAndSettle();
}

/// Lo que lee la prueba de la base, con el reloj de verdad.
Future<T> read<T>(WidgetTester tester, Future<T> Function() query) async =>
    (await tester.runAsync(query)) as T;

void main() {
  late StudyViewerHarness h;

  setUp(() async {
    h = await StudyViewerHarness.create();
    await h.processed('doc', 'Éxodo');
  });

  Future<StudyCreation> deck({
    bool inReview = false,
    bool withImage = false,
    Map<String, Object?> options = const {},
  }) async {
    // La ilustración, guardada en el almacén de siempre.
    final reference = withImage
        ? await h.container
              .read(creationIllustrationStoreProvider)
              .save(
                creationId: 'mazo',
                slotId: 'c1',
                bytes: tinyPng(),
                mimeType: 'image/png',
              )
        : null;
    return h.ready(
      StudyCreationKind.flashcards,
      FlashcardDeckJson.encodeString(
        _deck(inReview: inReview, illustrationRef: reference),
      ),
      options: options,
    );
  }

  String progress(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('deck-progress'))).data!;

  bool showsBack(WidgetTester tester) => tester
      .widget<ReviewFlipCard>(find.byKey(const Key('deck-card')).hitTestable())
      .showBack;

  testWidgets('la tarjeta de Repasar: «1 / 3», se da vuelta al tocarla, y '
      'anterior y siguiente', (tester) async {
    await h.open(tester, await deck());

    expect(find.byKey(const Key('deck-viewer')), findsOneWidget);
    expect(progress(tester), '1 / 3');
    expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);
    expect(showsBack(tester), isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('deck-previous')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('deck-card')).hitTestable());
    await tester.pumpAndSettle();
    expect(showsBack(tester), isTrue);
    expect(find.text('Moisés.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deck-next')));
    await tester.pumpAndSettle();
    expect(progress(tester), '2 / 3');
    // La siguiente arranca del frente.
    expect(showsBack(tester), isFalse);
    expect(find.text('¿Qué se abre?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deck-flip')));
    await tester.pumpAndSettle();
    expect(showsBack(tester), isTrue);

    await tester.tap(find.byKey(const Key('deck-previous')));
    await tester.pumpAndSettle();
    expect(progress(tester), '1 / 3');
  });

  testWidgets('se desliza a la siguiente, y la última no tiene siguiente', (
    tester,
  ) async {
    await h.open(tester, await deck());

    await tester.fling(
      find.byKey(const Key('deck-pages')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(progress(tester), '2 / 3');

    await tester.tap(find.byKey(const Key('deck-next')));
    await tester.pumpAndSettle();
    expect(progress(tester), '3 / 3');
    expect(
      tester.widget<IconButton>(find.byKey(const Key('deck-next'))).onPressed,
      isNull,
    );
  });

  testWidgets('la pista se ve al pedirla', (tester) async {
    await h.open(tester, await deck());

    expect(find.byKey(const Key('deck-card-hint')), findsNothing);
    await tester.tap(find.byKey(const Key('deck-show-hint')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Pista: Empieza con M.'), findsOneWidget);
    // Pedir la pista no da vuelta la tarjeta.
    expect(showsBack(tester), isFalse);
  });

  testWidgets('barajar no saca la tarjeta de la vista; volver al orden la '
      'deja en su lugar', (tester) async {
    await h.open(tester, await deck());
    await tester.tap(find.byKey(const Key('deck-next')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deck-shuffle')));
    await tester.pumpAndSettle();
    expect(progress(tester), '1 / 3');
    expect(find.text('¿Qué se abre?'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('deck-shuffle')))
          .isSelected,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('deck-shuffle')));
    await tester.pumpAndSettle();
    expect(progress(tester), '2 / 3');
    expect(find.text('¿Qué se abre?'), findsOneWidget);
  });

  testWidgets(
    '«Sumar a mi repaso» desde el visor: prenderlo pone las tres en '
    '«Para hoy» una sola vez, apagarlo las saca sin borrarlas, y queda '
    'guardado en el mazo',
    timeout: const Timeout(Duration(seconds: 90)),
    (tester) async {
      final created = await deck();
      final scope = StudyScope.processed(
        const CreationScope.document('doc').storageKey,
      );
      Future<int> dueToday() async =>
          (await h.container
                  .read(studyRepositoryProvider)
                  .counts(scope, limits: const StudyLimits(newPerDay: 999)))
              .getRight()
              .toNullable()!
              .newCards;
      Future<List<Flashcard>> cardsOf(String itemId) async => [
        for (final card
            in (await h.container.read(flashcardRepositoryProvider).getAll())
                .getRight()
                .toNullable()!)
          if (card.itemId == itemId) card,
      ];
      Future<FlashcardDeck> stored() async => FlashcardDeckJson.decode(
        (await h.creations.find(
          created.id,
        )).getRight().toNullable()!.decodedContent,
      );
      await h.open(tester, created);

      SwitchListTile toggle() => tester.widget<SwitchListTile>(
        find.byKey(const Key('deck-in-review')),
      );
      expect(toggle().value, isFalse);
      expect(
        find.text('Solo para hojear: no entran en tu repaso.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('deck-in-review')));
      await settleSaving(tester);
      expect(toggle().value, isTrue);
      expect((await read(tester, stored)).inReview, isTrue);
      expect(await read(tester, dueToday), 3);
      // Seguís en la misma tarjeta.
      expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deck-in-review')));
      await settleSaving(tester);
      expect(toggle().value, isFalse);
      expect(await read(tester, dueToday), 0);
      final cards = await read(tester, () => cardsOf('doc'));
      expect(cards, hasLength(3));
      expect(cards.every((c) => c.suspended), isTrue);

      await tester.tap(find.byKey(const Key('deck-in-review')));
      await settleSaving(tester);
      expect(await read(tester, dueToday), 3);
      expect(await read(tester, () => cardsOf('doc')), hasLength(3));
    },
  );

  testWidgets('con imágenes: la ilustración con IA donde salió, el dibujo de '
      'la app donde no, y por qué no hubo más', (tester) async {
    await h.open(
      tester,
      await deck(withImage: true, options: {CreationOptionValues.images: true}),
    );

    expect(find.byKey(const Key('study-illustration-notice')), findsOneWidget);
    expect(find.textContaining('no tiene facturación activa'), findsOneWidget);
    expect(find.byKey(const Key('study-item-image')), findsOneWidget);

    await tester.tap(find.byKey(const Key('deck-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('study-item-art')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('sin imágenes pedidas, ni ilustración ni dibujo', (tester) async {
    await h.open(tester, await deck());
    expect(find.byKey(const Key('study-item-art')), findsNothing);
    expect(find.byKey(const Key('study-illustration-notice')), findsNothing);
  });

  testWidgets('un mazo vacío lo dice', (tester) async {
    await h.open(
      tester,
      await h.ready(StudyCreationKind.flashcards, '{"cards": []}'),
    );
    expect(find.byKey(const Key('deck-viewer-empty')), findsOneWidget);
  });

  testWidgets('«Descargar» en la barra del visor', (tester) async {
    await h.open(tester, await deck());
    expect(find.byKey(const Key('study-download')), findsOneWidget);
  });

  testWidgets('a 360 de ancho con la letra al doble, en oscuro, sin '
      'desbordarse', (tester) async {
    await h.open(
      tester,
      await deck(withImage: true, options: {CreationOptionValues.images: true}),
      size: const Size(360, 780),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('deck-viewer-scroll')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('deck-flip')));
    await tester.tap(find.byKey(const Key('deck-flip')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('en los nueve temas se ve sin desbordarse', (tester) async {
    final created = await deck(
      withImage: true,
      options: {CreationOptionValues.images: true},
    );
    for (final theme in AppThemeChoice.values) {
      await h.open(tester, created, size: const Size(360, 780), theme: theme);
      expect(tester.takeException(), isNull, reason: theme.name);
      expect(find.byKey(const Key('deck-viewer')), findsOneWidget);
    }
  });
}
