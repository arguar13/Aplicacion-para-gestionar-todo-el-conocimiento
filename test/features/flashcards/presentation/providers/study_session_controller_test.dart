import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_counts.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_next.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/study_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_session_controller.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';

import '../../../../support/library_harness.dart';

/// Una cola que siempre falla, para el camino de «no se pudo leer».
class _FailingStudyRepository implements StudyRepository {
  @override
  Future<Either<Failure, StudyNext>> next(
    StudyScope scope, {
    required StudyLimits limits,
    Duration learnAhead = Duration.zero,
  }) async => left(const Failure.unexpected(message: 'se rompió la cola'));

  @override
  Future<Either<Failure, StudyCounts>> counts(
    StudyScope scope, {
    required StudyLimits limits,
  }) async => left(const Failure.unexpected(message: 'se rompió la cola'));

  @override
  Stream<StudyCounts> watchCounts(
    StudyScope scope, {
    required StudyLimits limits,
  }) => const Stream.empty();
}

/// La sesión de estudio sin pantalla (F31, ola 2): qué toca, qué se contestó,
/// deshacer y las acciones sobre la tarjeta que se ve.
void main() {
  const scope = StudyScope.all();
  late LibraryHarness harness;
  late String itemId;
  var now = DateTime(2026, 9, 11, 10);

  setUp(() async {
    now = DateTime(2026, 9, 11, 10);
    harness = await LibraryHarness.create(
      extraOverrides: [clockProvider.overrideWithValue(() => now)],
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
  });

  Future<List<Flashcard>> addCards(List<String> fronts) async => [
    for (final front in fronts)
      (await harness.container
              .read(flashcardRepositoryProvider)
              .create(itemId: itemId, front: front, back: 'R de $front'))
          .getRight()
          .toNullable()!,
  ];

  /// Abre la sesión y espera a que lea la cola.
  Future<StudySessionController> open([
    ProviderContainer? container,
    StudyScope sessionScope = scope,
  ]) async {
    final c = container ?? harness.container;
    final subscription = c.listen(
      studySessionProvider(sessionScope),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = c.read(studySessionProvider(sessionScope).notifier);
    await controller.start();
    return controller;
  }

  StudySessionState stateOf([StudyScope sessionScope = scope]) =>
      harness.container.read(studySessionProvider(sessionScope));

  Future<Flashcard> stored(String id) async =>
      (await harness.container.read(flashcardRepositoryProvider).getAll())
          .getRight()
          .toNullable()!
          .firstWhere((c) => c.id == id);

  test('al abrir, lee la cola: la primera tarjeta, sin la respuesta a la '
      'vista y con el conteo de hoy', () async {
    await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);

    await open();

    final state = stateOf();
    expect(state.card?.front, '¿Uno?');
    expect(state.queue, StudyQueueKind.newCard);
    expect(state.revealed, isFalse);
    expect(state.counts?.total, 3);
    expect(state.answered, 0);
    expect(state.progress, 0);
  });

  test('calificar exige tener la respuesta a la vista', () async {
    await addCards(['¿Uno?', '¿Dos?']);
    final controller = await open();

    final failure = await controller.grade(ReviewGrade.good);

    expect(failure, isNull);
    expect(stateOf().answered, 0);
    expect(stateOf().card?.front, '¿Uno?');
  });

  test('calificar guarda la respuesta, pasa a la siguiente y sube el '
      'avance', () async {
    await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
    final controller = await open();

    controller.reveal();
    expect(stateOf().revealed, isTrue);
    await controller.grade(ReviewGrade.easy);

    final state = stateOf();
    expect(state.answered, 1);
    expect(state.correct, 1);
    expect(state.card?.front, '¿Dos?');
    expect(state.revealed, isFalse);
    expect(state.busy, isFalse);
    expect(state.counts?.total, 2);
    expect(state.progress, closeTo(1 / 3, 1e-9));
  });

  test('«De nuevo» no cuenta como acierto, y la tarjeta vuelve a contar como '
      'pendiente', () async {
    await addCards(['¿Uno?']);
    final controller = await open();

    controller.reveal();
    await controller.grade(ReviewGrade.again);

    final state = stateOf();
    expect(state.answered, 1);
    expect(state.correct, 0);
    // Vuelve en 1 minuto: la sesión espera.
    expect(state.next, isA<StudyNextWait>());
    expect(state.counts?.learning, 1);
    expect(state.progress, closeTo(0.5, 1e-9));
  });

  test('el tiempo de cada respuesta es lo que pasó desde que se mostró, con '
      'un tope', () async {
    await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
    final controller = await open();

    now = now.add(const Duration(seconds: 20));
    controller.reveal();
    await controller.grade(ReviewGrade.good);
    // Dos horas con el teléfono sobre la mesa: cuenta el tope, no las horas.
    now = now.add(const Duration(hours: 2));
    controller.reveal();
    await controller.grade(ReviewGrade.good);

    final state = stateOf();
    expect(state.answers[0].took, const Duration(seconds: 20));
    expect(state.answers[1].took, StudySessionController.longestAnswer);
    expect(
      state.studied,
      const Duration(seconds: 20) + StudySessionController.longestAnswer,
    );
  });

  group('deshacer', () {
    test('devuelve la tarjeta a como estaba, la muestra otra vez sin la '
        'respuesta y descuenta la respuesta de la sesión', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();
      final before = await stored(cards.first.id);
      controller.reveal();
      await controller.grade(ReviewGrade.easy);
      expect(stateOf().card?.front, '¿Dos?');

      final failure = await controller.undo();

      expect(failure, isNull);
      final state = stateOf();
      expect(state.card?.id, cards.first.id);
      expect(state.revealed, isFalse);
      expect(state.answered, 0);
      expect(state.counts?.total, 2);
      final after = await stored(cards.first.id);
      expect(after.dueAt, before.dueAt);
      expect(after.repetitions, before.repetitions);
      expect(after.lastReviewedAt, before.lastReviewedAt);
    });

    test('se puede repetir, de la más nueva a la más vieja', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      final controller = await open();
      for (var i = 0; i < 2; i++) {
        controller.reveal();
        await controller.grade(ReviewGrade.good);
      }
      expect(stateOf().answered, 2);

      await controller.undo();
      expect(stateOf().card?.id, cards[1].id);
      await controller.undo();
      expect(stateOf().card?.id, cards[0].id);
      expect(stateOf().answered, 0);
      expect(controller.canUndo, isFalse);
    });

    test('sin respuestas en la sesión no hace nada, ni toca lo de antes de '
        'abrirla', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      // Lo de «ayer»: contestado antes de abrir la sesión.
      await harness.container
          .read(flashcardRepositoryProvider)
          .review(id: cards.first.id, grade: ReviewGrade.easy);
      now = now.add(const Duration(hours: 1));
      final controller = await open();

      final failure = await controller.undo();

      expect(failure, isNull);
      expect(controller.canUndo, isFalse);
      final card = await stored(cards.first.id);
      expect(card.repetitions, greaterThan(0));
    });

    test('devuelve por qué no se pudo, sin cambiar lo que se ve', () async {
      await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();
      controller.reveal();
      await controller.grade(ReviewGrade.good);
      // El historial ya no tiene esa respuesta (la limpió otra cosa): el
      // repositorio rechaza deshacer y la pantalla tiene que enterarse.
      await harness.database.delete(harness.database.reviewLogs).go();

      final failure = await controller.undo();

      expect(failure, isNotNull);
      expect(stateOf().answered, 1);
      expect(stateOf().card?.front, '¿Dos?');
      expect(stateOf().busy, isFalse);
    });

    test('borrar una tarjeta se lleva su historial: la lista de la sesión lo '
        'sigue y deshacer alcanza a la respuesta anterior', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      final controller = await open();
      controller.reveal();
      await controller.grade(ReviewGrade.again); // Uno vuelve en 1 minuto
      controller.reveal();
      await controller.grade(ReviewGrade.good); // Dos vuelve en 10
      // Tres sigue; se la deja y se pide «seguir ahora»: aparece Uno.
      controller.reveal();
      await controller.grade(ReviewGrade.easy); // Tres se gradúa
      await controller.continueNow();
      expect(stateOf().card?.id, cards[0].id);
      expect(stateOf().answered, 3);

      // Se borra Uno: su respuesta desaparece de la base, y de la sesión.
      await controller.deleteCurrent();
      expect(stateOf().answered, 2);

      // Deshacer alcanza ahora a la de Tres, la más nueva que queda.
      final failure = await controller.undo();

      expect(failure, isNull);
      expect(stateOf().card?.id, cards[2].id);
      expect(stateOf().answered, 1);
    });
  });

  group('«Estudiar más hoy» y «Seguir ahora»', () {
    test('estudiar más amplía el límite solo por hoy y sigue', () async {
      await harness.container
          .read(studyLimitsProvider.notifier)
          .setNewPerDay(1);
      await addCards(['¿Uno?', '¿Dos?', '¿Tres?']);
      final controller = await open();
      controller.reveal();
      await controller.grade(ReviewGrade.easy);
      final limit = stateOf().next! as StudyNextDone;
      expect(limit.hitLimit, isTrue);
      expect(limit.newBeyondLimit, 2);

      await controller.studyMore();

      expect(stateOf().card?.front, '¿Dos?');
      // Lo guardado no cambió.
      expect(harness.container.read(studyLimitsProvider).newPerDay, 1);
    });

    test(
      'seguir ahora trae la tarjeta que vuelve en un rato, una vez',
      () async {
        await addCards(['¿Uno?']);
        final controller = await open();
        controller.reveal();
        await controller.grade(ReviewGrade.good);
        expect(stateOf().next, isA<StudyNextWait>());

        await controller.continueNow();

        final state = stateOf();
        expect(state.card?.front, '¿Uno?');
        expect((state.next! as StudyNextCard).early, isTrue);

        // Se la contesta otra vez «De nuevo»: no queda un «seguir ahora»
        // pegado para siempre, la espera vuelve.
        controller.reveal();
        await controller.grade(ReviewGrade.again);
        expect(stateOf().next, isA<StudyNextWait>());
      },
    );
  });

  group('sobre la tarjeta que se ve', () {
    test('pausar la saca de la cola y devuelve su id; reactivarla la deja '
        'volver', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();

      final result = await controller.suspendCurrent();

      expect(result.failure, isNull);
      expect(result.id, cards.first.id);
      expect(stateOf().card?.id, cards[1].id);
      expect((await stored(cards.first.id)).suspended, isTrue);
      expect(stateOf().counts?.total, 1);

      await controller.restore(cards.first.id, wasSuspended: true);
      await pumpEventQueue();

      expect((await stored(cards.first.id)).suspended, isFalse);
      // La que se estaba viendo no se cambió debajo de la persona.
      expect(stateOf().card?.id, cards[1].id);
      expect(stateOf().counts?.total, 2);
    });

    test('posponer la deja para mañana; deshacerlo la devuelve', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();

      final result = await controller.buryCurrent();

      expect(result.id, cards.first.id);
      expect(stateOf().card?.id, cards[1].id);
      expect((await stored(cards.first.id)).buriedUntil, isNotNull);

      await controller.restore(cards.first.id, wasSuspended: false);

      expect((await stored(cards.first.id)).buriedUntil, isNull);
    });

    test('borrarla la saca de la base y de la cola', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();

      final failure = await controller.deleteCurrent();

      expect(failure, isNull);
      expect(stateOf().card?.id, cards[1].id);
      final all =
          (await harness.container.read(flashcardRepositoryProvider).getAll())
              .getRight()
              .toNullable()!;
      expect(all.map((c) => c.id), [cards[1].id]);
    });

    test('editarla cambia el texto y, si ya estaba revelada, la deja '
        'revelada', () async {
      final cards = await addCards(['¿Uno?', '¿Dos?']);
      final controller = await open();
      controller.reveal();

      final failure = await controller.editCurrent(
        front: '¿Uno, mejor escrito?',
        back: 'Una respuesta mejor',
      );

      expect(failure, isNull);
      final state = stateOf();
      expect(state.card?.id, cards.first.id);
      expect(state.card?.front, '¿Uno, mejor escrito?');
      expect(state.revealed, isTrue);
    });

    test('editarla con la respuesta en blanco devuelve el fallo y no cambia '
        'nada', () async {
      await addCards(['¿Uno?']);
      final controller = await open();

      final failure = await controller.editCurrent(front: '¿Uno?', back: ' ');

      expect(failure, isNotNull);
      expect(stateOf().card?.front, '¿Uno?');
    });
  });

  test('sin nada a la vista, un cambio en la base trae la tarjeta que '
      'aparece; con una a la vista no la cambia', () async {
    final controller = await open();
    expect(stateOf().next, isA<StudyNextDone>());

    final created = await addCards(['¿Nueva?']);
    controller.onStudyDataChanged();
    await pumpEventQueue();
    expect(stateOf().card?.id, created.single.id);

    // Con una a la vista, lo que aparece solo cambia el conteo, aunque la cola
    // la pondría primero: una tarjeta en aprendizaje que ya volvió va antes
    // que una nueva, y no por eso se le cambia la que está mirando.
    final other = (await addCards(['¿Otra?'])).single;
    await harness.container
        .read(flashcardRepositoryProvider)
        .review(id: other.id, grade: ReviewGrade.good);
    now = now.add(const Duration(minutes: 11));
    controller.onStudyDataChanged();
    await pumpEventQueue();
    expect(stateOf().card?.id, created.single.id);
    expect(stateOf().counts?.total, 2);
  });

  test('si la cola no se puede leer, lo dice y deja reintentar', () async {
    final failing = await LibraryHarness.create(
      extraOverrides: [
        studyRepositoryProvider.overrideWithValue(_FailingStudyRepository()),
      ],
    );
    final controller = await open(failing.container);

    final state = failing.container.read(studySessionProvider(scope));
    expect(state.failure, isNotNull);
    expect(state.next, isNull);
    expect(state.busy, isFalse);

    await controller.retry();
    expect(
      failing.container.read(studySessionProvider(scope)).failure,
      isNotNull,
    );
  });
}
