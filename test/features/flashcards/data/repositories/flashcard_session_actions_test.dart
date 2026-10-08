import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/flashcards/data/repositories/flashcard_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/habit/data/repositories/badge_repository_impl.dart';
import 'package:sinapsis/features/habit/data/repositories/streak_repository_impl.dart';
import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/item_rows.dart';

class _MockTelemetry extends Mock implements TelemetryService {}

/// Lo que se hace con una tarjeta durante la sesión (F31, decisión 69):
/// deshacer la última respuesta, pausar y posponer.
void main() {
  late AppDatabase db;
  late FlashcardRepositoryImpl repository;
  var now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    now = DateTime(2026, 10, 8, 10);
    db = AppDatabase(NativeDatabase.memory());
    repository = FlashcardRepositoryImpl(
      database: db,
      telemetry: _MockTelemetry(),
      ids: FakeIdGenerator(),
      clock: () => now,
    );
    await insertItemRows(db, id: 'item', title: 'Un elemento');
  });

  tearDown(() => db.close());

  Future<String> newCard([String front = 'P']) async =>
      (await repository.create(
        itemId: 'item',
        front: front,
        back: 'R',
      )).getRight().toNullable()!.id;

  /// Lo que un repaso toca: las tarjetas y el historial, tal cual.
  Future<({List<FlashcardRow> cards, List<ReviewLogRow> logs})> dump() async {
    final cards = await (db.select(
      db.flashcards,
    )..orderBy([(f) => OrderingTerm(expression: f.id)])).get();
    final logs = await (db.select(
      db.reviewLogs,
    )..orderBy([(r) => OrderingTerm(expression: r.id)])).get();
    return (cards: cards, logs: logs);
  }

  Future<FlashcardRow> row(String id) =>
      (db.select(db.flashcards)..where((f) => f.id.equals(id))).getSingle();

  /// Deja la tarjeta [id] en la etapa [phase], escribiendo directo.
  Future<void> putInPhase(String id, CardPhase phase) {
    final values = switch (phase) {
      CardPhase.newCard => const FlashcardsCompanion(),
      CardPhase.learning => FlashcardsCompanion(
        learningStep: const Value(1),
        lastReviewedAt: Value(now.subtract(const Duration(minutes: 10))),
        dueAt: Value(now),
      ),
      CardPhase.relearning => FlashcardsCompanion(
        intervalDays: const Value(1),
        easeFactor: const Value(1.7),
        learningStep: const Value(0),
        lastReviewedAt: Value(now.subtract(const Duration(minutes: 10))),
        dueAt: Value(now),
      ),
      CardPhase.review => FlashcardsCompanion(
        repetitions: const Value(4),
        intervalDays: const Value(30),
        easeFactor: const Value(2.3),
        lastReviewedAt: Value(now.subtract(const Duration(days: 30))),
        dueAt: Value(now),
      ),
    };
    return (db.update(
      db.flashcards,
    )..where((f) => f.id.equals(id))).write(values);
  }

  group('deshacer la última respuesta', () {
    test('repasar y deshacer deja la base idéntica, en cada etapa y con cada '
        'respuesta', () async {
      for (final phase in CardPhase.values) {
        for (final grade in ReviewGrade.values) {
          final id = await newCard('P-${phase.name}-${grade.name}');
          await putInPhase(id, phase);
          final before = await dump();

          await repository.review(id: id, grade: grade);
          expect(
            (await dump()).logs.length,
            before.logs.length + 1,
            reason: '${phase.name} ${grade.name}: dejó su renglón',
          );
          final undone = await repository.undoLastReview();

          expect(undone.isRight(), isTrue, reason: '${phase.name} $grade');
          final after = await dump();
          expect(after.cards, before.cards, reason: '${phase.name} $grade');
          expect(after.logs, before.logs, reason: '${phase.name} $grade');
          expect(
            undone.getRight().toNullable()!.id,
            id,
            reason: 'devuelve la tarjeta restaurada',
          );
        }
      }
    });

    test('devuelve la tarjeta como quedó', () async {
      final id = await newCard();
      await putInPhase(id, CardPhase.review);
      final before = await row(id);
      await repository.review(id: id, grade: ReviewGrade.easy);

      final restored = (await repository.undoLastReview())
          .getRight()
          .toNullable()!;

      expect(restored.easeFactor, before.easeFactor);
      expect(restored.intervalDays, before.intervalDays);
      expect(restored.repetitions, before.repetitions);
      expect(restored.dueAt, before.dueAt);
      expect(restored.lastReviewedAt, before.lastReviewedAt);
      expect(restored.learningStep, before.learningStep);
    });

    test('varias seguidas, aunque todas pasaron en el mismo segundo: de la más '
        'nueva a la más vieja', () async {
      final id = await newCard();
      final states = <FlashcardRow>[await row(id)];
      for (final grade in [
        ReviewGrade.again,
        ReviewGrade.good,
        ReviewGrade.good,
        ReviewGrade.easy,
      ]) {
        // El reloj no avanza: cuatro respuestas con el mismo `reviewed_at`.
        await repository.review(id: id, grade: grade);
        states.add(await row(id));
      }

      for (var i = states.length - 2; i >= 0; i--) {
        final result = await repository.undoLastReview();
        expect(result.isRight(), isTrue, reason: 'deshacer #$i');
        expect(await row(id), states[i], reason: 'quedó en el paso $i');
      }
      expect((await dump()).logs, isEmpty);
      expect((await repository.undoLastReview()).isLeft(), isTrue);
    });

    test('deshace la más reciente aunque sea de otra tarjeta', () async {
      final a = await newCard('A');
      final b = await newCard('B');
      await repository.review(id: a, grade: ReviewGrade.good);
      now = now.add(const Duration(minutes: 1));
      final aAfter = await row(a);
      await repository.review(id: b, grade: ReviewGrade.good);

      final undone = (await repository.undoLastReview())
          .getRight()
          .toNullable()!;

      expect(undone.id, b);
      expect(await row(a), aAfter, reason: 'la otra no se tocó');
      expect((await row(b)).learningStep, isNull);
    });

    test('sin nada que deshacer, lo dice y no toca nada', () async {
      await newCard();
      final before = await dump();

      final result = await repository.undoLastReview();

      expect(result.isLeft(), isTrue);
      expect((await dump()).cards, before.cards);
    });

    test('con `since`, solo deshace lo de esa sesión en adelante', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.good);
      final afterFirst = await row(id);

      // La sesión empezó DESPUÉS de esa respuesta: no hay nada para deshacer.
      final sessionStart = now.add(const Duration(minutes: 5));
      expect(
        (await repository.undoLastReview(since: sessionStart)).isLeft(),
        isTrue,
      );
      expect(await row(id), afterFirst);

      // Si la sesión empezó antes o justo en ese momento, sí.
      expect((await repository.undoLastReview(since: now)).isRight(), isTrue);
    });

    test('un repaso de antes de v39, del que no se guardó cómo estaba la '
        'tarjeta, no se deshace', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.good);
      await db.customStatement('UPDATE review_log SET due_before = NULL');
      final before = await dump();

      final result = await repository.undoLastReview();

      expect(result.isLeft(), isTrue);
      final after = await dump();
      expect(after.cards, before.cards);
      expect(after.logs, before.logs);
    });

    test('si la tarjeta cambió después (un repaso más nuevo de otro '
        'dispositivo), no pisa nada', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.good);
      // Otro dispositivo la repasó más tarde: su renglón y su estado.
      final later = now.add(const Duration(hours: 1));
      await db.customStatement(
        'INSERT INTO review_log (id, flashcard_id, reviewed_at, grade, '
        'quality, interval_before, interval_after, ease_before, ease_after, '
        "device_id) VALUES ('remoto', '$id', "
        "${later.millisecondsSinceEpoch ~/ 1000}, 'good', 4, 0, 1, 2.5, 2.5, "
        "'otro')",
      );
      await (db.update(db.flashcards)..where((f) => f.id.equals(id))).write(
        FlashcardsCompanion(lastReviewedAt: Value(later)),
      );
      final before = await dump();

      final result = await repository.undoLastReview();

      expect(result.isLeft(), isTrue);
      final after = await dump();
      expect(after.cards, before.cards);
      expect(after.logs, before.logs);
    });

    test('una tarjeta borrada no deja nada que deshacer', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.good);
      await repository.delete(id);

      expect((await repository.undoLastReview()).isLeft(), isTrue);
    });

    test('el hábito se deshace con la respuesta: la racha y las insignias '
        'salen del historial', () async {
      final streaks = StreakRepositoryImpl(
        database: db,
        telemetry: _MockTelemetry(),
        clock: () => now,
      );
      final id = await newCard();
      expect((await streaks.current()).days, 0);

      await repository.review(id: id, grade: ReviewGrade.good);
      final withReview = await streaks.current();
      expect(withReview.days, 1);
      expect(withReview.activeToday, isTrue);

      await repository.undoLastReview();

      final withoutReview = await streaks.current();
      expect(withoutReview.days, 0);
      expect(withoutReview.activeToday, isFalse);
    });

    test(
      'la insignia de los cien repasos se va si el repaso 100 se deshace',
      () async {
        final badges = BadgeRepositoryImpl(
          database: db,
          telemetry: _MockTelemetry(),
          clock: () => now,
        );
        final id = await newCard();
        for (var i = 0; i < 100; i++) {
          await repository.review(id: id, grade: ReviewGrade.good);
        }
        expect(await badges.earned(), contains(BadgeKind.hundredReviews));

        await repository.undoLastReview();

        expect(
          await badges.earned(),
          isNot(contains(BadgeKind.hundredReviews)),
        );
      },
    );
  });

  group('pausar', () {
    test('suspend y unsuspend, de a varias, sin tocar el calendario', () async {
      final a = await newCard('A');
      final b = await newCard('B');
      final c = await newCard('C');
      await repository.review(id: a, grade: ReviewGrade.easy);
      final aBefore = await row(a);

      await repository.suspend([a, b]);

      expect((await row(a)).suspended, isTrue);
      expect((await row(b)).suspended, isTrue);
      expect((await row(c)).suspended, isFalse);
      expect(
        (await row(a)).dueAt,
        aBefore.dueAt,
        reason: 'el calendario no cambia',
      );
      expect((await row(a)).intervalDays, aBefore.intervalDays);

      await repository.unsuspend([a]);

      expect((await row(a)).suspended, isFalse);
      expect((await row(b)).suspended, isTrue);
      expect(await row(a), aBefore);
    });

    test('ids que no existen o una lista vacía no son un error', () async {
      final a = await newCard();

      expect((await repository.suspend(const [])).isRight(), isTrue);
      expect((await repository.suspend(['no-existe'])).isRight(), isTrue);
      expect((await repository.unsuspend(['no-existe', a])).isRight(), isTrue);
    });
  });

  group('posponer hasta mañana', () {
    test('queda hasta las 4:00 del próximo día de estudio', () async {
      final id = await newCard();

      await repository.buryUntilTomorrow([id]);

      expect((await row(id)).buriedUntil, DateTime(2026, 10, 9, 4));
    });

    test('de madrugada, "mañana" es esta misma mañana a las 4:00', () async {
      now = DateTime(2026, 10, 8, 1, 30);
      final id = await newCard();

      await repository.buryUntilTomorrow([id]);

      expect((await row(id)).buriedUntil, DateTime(2026, 10, 8, 4));
    });

    test('unbury la devuelve, y no toca el calendario', () async {
      final id = await newCard();
      await repository.review(id: id, grade: ReviewGrade.easy);
      final before = await row(id);

      await repository.buryUntilTomorrow([id]);
      await repository.unbury([id]);

      expect(await row(id), before);
    });

    test('varias a la vez', () async {
      final a = await newCard('A');
      final b = await newCard('B');

      await repository.buryUntilTomorrow([a, b]);

      expect((await row(a)).buriedUntil, isNotNull);
      expect((await row(b)).buriedUntil, isNotNull);
    });
  });
}
