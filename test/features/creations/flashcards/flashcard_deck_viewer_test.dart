import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/flashcards/domain/flashcard_deck.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/presentation/explain_in_chat_question.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_illustration_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/review_flip_card.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

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

/// Deja que la base de la prueba termine lo que tenga en camino —guardar una
/// calificación, leer las tarjetas de nuevo—: avanza con el reloj de verdad.
Future<void> settleDatabase(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Lo que lee la prueba de la base, con el reloj de verdad.
Future<T> read<T>(WidgetTester tester, Future<T> Function() query) async =>
    (await tester.runAsync(query)) as T;

void main() {
  final es = AppLocalizationsEs();
  late StudyViewerHarness h;

  setUp(() async {
    h = await StudyViewerHarness.create();
    await h.processed('doc', 'Éxodo');
  });

  Future<StudyCreation> deck({
    WidgetTester? inReviewWith,
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
    var content = _deck(illustrationRef: reference);
    // Sumado al repaso como lo suma la app: cada tarjeta con la suya en el
    // documento, con su calendario. Leer las tarjetas del documento es un
    // `Stream` de la base: avanza con el reloj de verdad.
    if (inReviewWith case final tester?) {
      final added = content;
      content = (await read(
        tester,
        () => h.container
            .read(deckReviewProvider)
            .add(added, fallbackDocument: 'doc'),
      )).getOrElse((f) => throw StateError('$f'));
    }
    return h.ready(
      StudyCreationKind.flashcards,
      FlashcardDeckJson.encodeString(content),
      options: options,
    );
  }

  Future<List<Flashcard>> cardsOf(String itemId) async => [
    for (final card
        in (await h.container.read(flashcardRepositoryProvider).getAll())
            .getRight()
            .toNullable()!)
      if (card.itemId == itemId) card,
  ];

  String progress(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('deck-progress'))).data!;

  bool showsBack(WidgetTester tester) => tester
      .widget<ReviewFlipCard>(find.byKey(const Key('deck-card')))
      .showBack;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Muestra la respuesta y califica con [grade], esperando a que se guarde.
  Future<void> answer(WidgetTester tester, String grade) async {
    await tapKey(tester, 'deck-show-answer');
    await tapKey(tester, 'grade-$grade');
    await settleDatabase(tester);
  }

  /// Cuántos textos tiene un botón de calificar: el nombre y, con
  /// calendario, cuándo vuelve.
  int textsIn(WidgetTester tester, String grade) => tester
      .widgetList(
        find.descendant(
          of: find.byKey(Key('grade-$grade')),
          matching: find.byType(Text),
        ),
      )
      .length;

  group('como en Anki, con «Sumar a mi repaso»', () {
    testWidgets('se ve la pregunta; «Mostrar respuesta» la da vuelta y '
        'aparecen los cuatro botones con su intervalo de SM-2', (tester) async {
      await h.open(tester, await deck(inReviewWith: tester));
      await settleDatabase(tester);

      expect(find.byKey(const Key('deck-viewer')), findsOneWidget);
      expect(progress(tester), '1 / 3');
      expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);
      expect(showsBack(tester), isFalse);
      expect(find.byKey(const Key('grade-good')), findsNothing);
      // Antes de dar vuelta, ni la fuente ni «Explicar».
      expect(find.byKey(const Key('deck-explain')), findsNothing);

      await tapKey(tester, 'deck-show-answer');
      expect(showsBack(tester), isTrue);
      expect(find.text('Moisés.'), findsOneWidget);
      for (final grade in ['again', 'hard', 'good', 'easy']) {
        expect(textsIn(tester, grade), 2, reason: grade);
      }
      expect(find.byKey(const Key('deck-practice-note')), findsNothing);
      expect(find.byKey(const Key('deck-swipe-hint')), findsOneWidget);
      expect(find.byKey(const Key('deck-view-source')), findsOneWidget);
      expect(find.byKey(const Key('deck-explain')), findsOneWidget);
    });

    testWidgets('tocar la tarjeta también muestra la respuesta', (
      tester,
    ) async {
      await h.open(tester, await deck(inReviewWith: tester));
      await settleDatabase(tester);

      await tester.tap(find.byKey(const Key('deck-card')));
      await tester.pumpAndSettle();
      expect(showsBack(tester), isTrue);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
    });

    testWidgets(
      'la calificación llega al calendario de la tarjeta del documento, con '
      'el mismo repositorio que la sesión de Repasar',
      timeout: const Timeout(Duration(seconds: 90)),
      (tester) async {
        final created = await deck(inReviewWith: tester);
        final linked = FlashcardDeckJson.decode(
          created.decodedContent,
        ).cards.first.flashcardId!;
        await h.open(tester, created);
        await settleDatabase(tester);

        await answer(tester, 'easy');

        expect(progress(tester), '2 / 3');
        expect(find.text('¿Qué se abre?'), findsOneWidget);
        final card = (await read(
          tester,
          () => cardsOf('doc'),
        )).singleWhere((c) => c.id == linked);
        expect(card.lastReviewedAt, isNotNull);
        expect(card.intervalDays, greaterThan(0));
        // Y en el registro de repasos, de donde salen la racha y el
        // historial.
        final logs = await read(
          tester,
          () => h.library.database.select(h.library.database.reviewLogs).get(),
        );
        expect(logs.map((l) => l.flashcardId), [linked]);
        expect(logs.single.grade, 'easy');
      },
    );

    testWidgets('«De nuevo» la vuelve a poner en la vuelta', (tester) async {
      await h.open(tester, await deck(inReviewWith: tester));
      await settleDatabase(tester);

      await answer(tester, 'again');
      expect(progress(tester), '2 / 4');
      await answer(tester, 'good');
      await answer(tester, 'good');
      expect(progress(tester), '4 / 4');
      expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);
      await answer(tester, 'good');

      expect(find.byKey(const Key('deck-summary')), findsOneWidget);
      String tally(String grade) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key('deck-tally-$grade')),
              matching: find.byKey(const Key('deck-tally-count')),
            ),
          )
          .data!;
      expect(tally('again'), '1');
      expect(tally('good'), '3');
      expect(tally('hard'), '0');
      expect(tally('easy'), '0');
      expect(find.text(es.f43S19DeckDoneScheduled), findsOneWidget);
      expect(find.text('3 tarjetas · 4 respuestas'), findsOneWidget);

      // Otra vuelta solo con la de «De nuevo».
      await tapKey(tester, 'deck-again-only');
      expect(progress(tester), '1 / 1');
      expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);
    });

    testWidgets(
      'deslizar la tarjeta dada vuelta califica, igual que en Repasar',
      timeout: const Timeout(Duration(seconds: 90)),
      (tester) async {
        await h.open(tester, await deck(inReviewWith: tester));
        await settleDatabase(tester);

        // Sin dar vuelta, deslizar no hace nada.
        await tester.drag(
          find.byKey(const Key('deck-swipe')),
          const Offset(300, 0),
        );
        await tester.pumpAndSettle();
        expect(progress(tester), '1 / 3');

        await tapKey(tester, 'deck-show-answer');
        await tester.drag(
          find.byKey(const Key('deck-swipe')),
          const Offset(300, 0),
        );
        await tester.pumpAndSettle();
        await settleDatabase(tester);
        expect(progress(tester), '2 / 3');
        final logs = await read(
          tester,
          () => h.library.database.select(h.library.database.reviewLogs).get(),
        );
        expect(logs.single.grade, 'good');
      },
    );

    testWidgets('«Explicar» lleva al chat la pregunta y la respuesta, con '
        'el título de su documento', (tester) async {
      final handoffs = <ChatHandoff>[];
      h.container.listen(chatHandoffProvider, (_, next) {
        if (next != null) handoffs.add(next);
      });
      await h.open(tester, await deck(inReviewWith: tester));
      await settleDatabase(tester);

      await tapKey(tester, 'deck-show-answer');
      await tester.tap(find.byKey(const Key('deck-explain')));
      await settleDatabase(tester);

      expect(handoffs, [
        ChatHandoff(
          question: explainInChatQuestion(
            es,
            const ExplainSubject(
              question: '¿Quién guía al pueblo?',
              answer: 'Moisés.',
              answered: true,
              sourceTitle: 'Éxodo',
            ),
          ),
        ),
      ]);
    });
  });

  group('con «Sumar a mi repaso» apagado', () {
    testWidgets(
      'se califica de práctica, lo dice, no toca ningún calendario y la '
      'vuelta suma a la racha',
      timeout: const Timeout(Duration(seconds: 90)),
      (tester) async {
        await h.open(tester, await deck());
        expect(find.text(es.f43S19DeckInReviewOff), findsOneWidget);

        await tapKey(tester, 'deck-show-answer');
        expect(find.byKey(const Key('deck-practice-note')), findsOneWidget);
        expect(find.text(es.f43S19DeckPracticeNote), findsOneWidget);
        // Sin calendario, sin intervalo debajo del nombre.
        for (final grade in ['again', 'hard', 'good', 'easy']) {
          expect(textsIn(tester, grade), 1, reason: grade);
        }
        await tapKey(tester, 'grade-good');
        await answer(tester, 'hard');
        await answer(tester, 'easy');
        await settleDatabase(tester);

        expect(find.byKey(const Key('deck-summary')), findsOneWidget);
        expect(find.text(es.f43S19DeckDonePractice), findsOneWidget);
        expect(find.byKey(const Key('deck-again-only')), findsNothing);
        expect(await read(tester, () => cardsOf('doc')), isEmpty);
        final events = await read(
          tester,
          () => h.library.database.select(h.library.database.habitEvents).get(),
        );
        expect(events.map((e) => e.kind), [HabitEventKind.quiz]);

        await tapKey(tester, 'deck-restart');
        expect(progress(tester), '1 / 3');
      },
    );

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

        await tester.tap(find.byKey(const Key('deck-in-review')));
        await settleSaving(tester);
        expect(toggle().value, isTrue);
        expect((await read(tester, stored)).inReview, isTrue);
        expect(await read(tester, dueToday), 3);
        // Seguís en la misma tarjeta, y ya con calendario.
        expect(find.text('¿Quién guía al pueblo?'), findsOneWidget);
        await tapKey(tester, 'deck-show-answer');
        await settleDatabase(tester);
        expect(find.byKey(const Key('deck-practice-note')), findsNothing);
        expect(textsIn(tester, 'good'), 2);

        await tester.tap(find.byKey(const Key('deck-in-review')));
        await settleSaving(tester);
        expect(toggle().value, isFalse);
        expect(await read(tester, dueToday), 0);
        final cards = await read(tester, () => cardsOf('doc'));
        expect(cards, hasLength(3));
        expect(cards.every((c) => c.suspended), isTrue);
        // Pausadas, se califican de práctica.
        expect(find.byKey(const Key('deck-practice-note')), findsOneWidget);

        await tester.tap(find.byKey(const Key('deck-in-review')));
        await settleSaving(tester);
        expect(await read(tester, dueToday), 3);
        expect(await read(tester, () => cardsOf('doc')), hasLength(3));
      },
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
    await answer(tester, 'good');
    expect(find.text('¿Qué se abre?'), findsOneWidget);

    await tapKey(tester, 'deck-shuffle');
    expect(progress(tester), '2 / 3');
    expect(find.text('¿Qué se abre?'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('deck-shuffle')))
          .isSelected,
      isTrue,
    );

    await tapKey(tester, 'deck-shuffle');
    expect(find.text('¿Qué se abre?'), findsOneWidget);
    await answer(tester, 'good');
    expect(find.text('¿Adónde llegan?'), findsOneWidget);
  });

  testWidgets('con imágenes: la ilustración con IA donde salió, el dibujo de '
      'la app donde no, y por qué no hubo más', (tester) async {
    await h.open(
      tester,
      await deck(withImage: true, options: {CreationOptionValues.images: true}),
    );

    expect(find.byKey(const Key('study-illustration-notice')), findsOneWidget);
    expect(find.textContaining('no tiene facturación activa'), findsOneWidget);
    expect(find.byKey(const Key('study-item-image')), findsOneWidget);

    await answer(tester, 'good');
    expect(find.byKey(const Key('study-item-art')), findsOneWidget);
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
      'desbordarse —de frente, dada vuelta y en el resumen—', (tester) async {
    await h.open(
      tester,
      await deck(withImage: true, options: {CreationOptionValues.images: true}),
      size: const Size(360, 780),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('deck-viewer-scroll')), findsOneWidget);
    await tapKey(tester, 'deck-show-answer');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'grade-again');
    await answer(tester, 'good');
    await answer(tester, 'good');
    await answer(tester, 'good');
    expect(find.byKey(const Key('deck-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en los nueve temas se ve sin desbordarse, dada vuelta', (
    tester,
  ) async {
    final created = await deck(
      withImage: true,
      options: {CreationOptionValues.images: true},
    );
    for (final theme in AppThemeChoice.values) {
      await h.open(tester, created, size: const Size(360, 780), theme: theme);
      // La app se vuelve a montar con el mismo visor: la tarjeta sigue dada
      // vuelta desde el tema anterior.
      if (find.byKey(const Key('deck-show-answer')).evaluate().isNotEmpty) {
        await tapKey(tester, 'deck-show-answer');
      }
      expect(tester.takeException(), isNull, reason: theme.name);
      expect(find.byKey(const Key('grade-good')), findsOneWidget);
    }
  });
}
