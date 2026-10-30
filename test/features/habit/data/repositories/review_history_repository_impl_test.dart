import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/habit/data/repositories/review_history_repository_impl.dart';
import 'package:sinapsis/features/habit/domain/entities/true_retention.dart';

import '../../../../support/card_browser_harness.dart';
import '../../../../support/item_rows.dart';

/// [ReviewHistoryRepositoryImpl] contra SQLite real, en memoria (F17, D8;
/// F43, M16): la curva y la retención real, el calendario con sus rachas y
/// las tarjetas que de verdad cuestan, siguiendo al recorte.
void main() {
  late CardBrowserHarness h;
  late ReviewHistoryRepositoryImpl repository;
  // Jueves 8 de octubre de 2026, 10:00: el día de estudio empezó a las 4:00.
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    h = await CardBrowserHarness.create(clock: () => now);
    repository = ReviewHistoryRepositoryImpl(
      database: h.db,
      telemetry: h.telemetry,
      clock: () => now,
      resolver: h.resolver,
    );
  });

  tearDown(() => h.close());

  DateTime daysAgo(int days, {int hour = 12}) =>
      DateTime(2026, 10, 8 - days, hour);

  /// Un repaso en días (joven con [before] < 21, maduro si no).
  Future<void> review(
    String card,
    DateTime at, {
    String grade = 'good',
    int before = 5,
  }) => h.answered(
    card,
    phase: CardPhase.review,
    at: at,
    grade: grade,
    intervalBefore: before,
  );

  test('sin repasos, todo viene en cero y sin difíciles', () async {
    final history = await repository.current(const StudyScope.all());
    expect(history.retentionByWeek, hasLength(12));
    expect(history.retentionByWeek.every((w) => w.total == 0), isTrue);
    expect(history.activityByDay, hasLength(365));
    expect(history.activityByDay.every((d) => d.count == 0), isTrue);
    expect(history.trueRetention, hasLength(RetentionPeriod.values.length));
    expect(history.trueRetention.every((r) => r.total.ratio == null), isTrue);
    expect(history.hardestCards, isEmpty);
    expect(history.currentRun, 0);
    expect(history.longestRun, 0);
  });

  group('la retención por semana', () {
    test('cuenta los repasos en días y se recordó todo lo que no fue «De '
        'nuevo»', () async {
      await h.card('c');
      await review('c', now);
      await review('c', now, grade: 'hard');
      await review('c', now, grade: 'easy');
      await review('c', now, grade: 'again');
      // Las nuevas y los pasos de minutos no dicen cuánto se retiene.
      await h.answered('c', phase: CardPhase.newCard, at: now, grade: 'again');
      await h.answered('c', phase: CardPhase.learning, at: now);

      final week = (await repository.current(
        const StudyScope.all(),
      )).retentionByWeek.last;
      expect(week.total, 4);
      expect(week.retained, 3);
      expect(week.ratio, 0.75);
      expect(week.weekStart, DateTime(2026, 10, 2, 4));
    });

    test('la semana corta por día de estudio, hacia atrás desde hoy', () async {
      await h.card('c');
      // Hace 7 días ya es la semana anterior; a las 3:00 de hoy, todavía
      // ayer.
      await review('c', daysAgo(7));
      await review('c', DateTime(2026, 10, 2, 3));
      await review('c', DateTime(2026, 10, 2, 4));

      final weeks = (await repository.current(
        const StudyScope.all(),
      )).retentionByWeek;
      expect(weeks.last.total, 1);
      expect(weeks[weeks.length - 2].total, 2);
    });
  });

  group('la retención real (como en Anki)', () {
    test('cada tramo, separado en jóvenes y maduras', () async {
      await h.card('c');
      await review('c', now);
      await review('c', now, grade: 'again');
      await review('c', now, before: 30);
      await review('c', daysAgo(1), before: 30, grade: 'again');
      await review('c', daysAgo(6));
      await review('c', daysAgo(20), before: 40);
      await review('c', daysAgo(200), grade: 'again');
      await review('c', daysAgo(400));

      final rows = {
        for (final row in (await repository.current(
          const StudyScope.all(),
        )).trueRetention)
          row.period: row,
      };
      PassFail young(RetentionPeriod p) => rows[p]!.young;
      PassFail mature(RetentionPeriod p) => rows[p]!.mature;

      expect(
        (
          young(RetentionPeriod.today).passed,
          young(RetentionPeriod.today).failed,
        ),
        (1, 1),
      );
      expect(mature(RetentionPeriod.today).passed, 1);
      expect(young(RetentionPeriod.yesterday).total, 0);
      expect(mature(RetentionPeriod.yesterday).failed, 1);
      expect(young(RetentionPeriod.week).total, 3);
      expect(mature(RetentionPeriod.week).total, 2);
      expect(mature(RetentionPeriod.month).total, 3);
      expect(young(RetentionPeriod.year).total, 4);
      expect(rows[RetentionPeriod.year]!.total.total, 7);
      expect(rows[RetentionPeriod.today]!.total.ratio, 2 / 3);
    });
  });

  group('la constancia', () {
    test('cada día con sus respuestas y su acierto', () async {
      await h.card('c');
      await review('c', now);
      await review('c', now, grade: 'again');
      await h.answered('c', phase: CardPhase.newCard, at: daysAgo(2));

      final days = (await repository.current(
        const StudyScope.all(),
      )).activityByDay;
      expect(days.last.day, DateTime(2026, 10, 8, 4));
      expect(days.last.count, 2);
      expect(days.last.correct, 1);
      expect(days.last.accuracy, 0.5);
      expect(days[days.length - 3].count, 1);
      expect(days[days.length - 2].accuracy, isNull);
    });

    test('la racha actual y la más larga, sobre todo el historial', () async {
      await h.card('c');
      // Una tirada vieja de cuatro días, una de dos que llega hasta ayer.
      for (final d in [300, 299, 298, 297, 2, 1]) {
        await review('c', daysAgo(d));
      }
      var history = await repository.current(const StudyScope.all());
      // Hoy todavía no: la racha cuenta hasta ayer, el día no terminó.
      expect(history.currentRun, 2);
      expect(history.longestRun, 4);

      await review('c', now);
      history = await repository.current(const StudyScope.all());
      expect(history.currentRun, 3);
    });
  });

  group('las tarjetas difíciles (el arreglo de raíz)', () {
    test(
      'una que nunca se olvidó no aparece, aunque tenga muchos repasos',
      () async {
        await h.card('facil', front: 'Fácil');
        for (var n = 0; n < 9; n++) {
          await review('facil', daysAgo(n));
        }
        await h.card('dificil', front: 'Difícil');
        await review('dificil', daysAgo(3), grade: 'again');
        await review('dificil', daysAgo(2));
        await review('dificil', daysAgo(1));

        final hardest = (await repository.current(
          const StudyScope.all(),
        )).hardestCards;
        expect([for (final c in hardest) c.flashcardId], ['dificil']);
        expect(hardest.every((c) => c.againCount >= 1), isTrue);
      },
    );

    test('por debajo del piso de repasos, no aparece', () async {
      await h.card('c');
      await review('c', now, grade: 'again');
      await review('c', now, grade: 'again');
      expect(
        (await repository.current(const StudyScope.all())).hardestCards,
        isEmpty,
      );
    });

    test('ordenadas por los lapsos, con sus números y su fuente', () async {
      await h.card('a', front: 'A', back: 'Respuesta A');
      // Tres «De nuevo» de nueva o aprendiendo: no son lapsos.
      await h.answered('a', phase: CardPhase.newCard, at: now, grade: 'again');
      await h.answered('a', phase: CardPhase.learning, at: now, grade: 'again');
      await h.answered('a', phase: CardPhase.learning, at: now, grade: 'again');
      await review('a', now);
      await h.card('b', front: 'B');
      for (var n = 0; n < 7; n++) {
        await review('b', daysAgo(n), grade: n < 2 ? 'again' : 'good');
      }
      await (h.db.update(
        h.db.flashcards,
      )..where((f) => f.id.equals('a'))).write(
        const FlashcardsCompanion(
          sourceCharStart: Value(10),
          sourceCharEnd: Value(40),
        ),
      );

      final hardest = (await repository.current(
        const StudyScope.all(),
      )).hardestCards;
      expect([for (final c in hardest) c.flashcardId], ['b', 'a']);
      final b = hardest.first;
      expect((b.againCount, b.total, b.lapses), (2, 7, 2));
      final a = hardest.last;
      expect((a.againCount, a.total, a.lapses), (3, 4, 0));
      expect(a.back, 'Respuesta A');
      expect(a.itemId, 'item');
      expect(a.hasSourceRange, isTrue);
      expect((a.sourceStart, a.sourceEnd), (10, 40));
      expect(b.hasSourceRange, isFalse);
    });

    test('una tarjeta de un elemento en la papelera no aparece', () async {
      await insertItemRows(h.db, id: 'borrado', title: 'Borrado');
      await h.card('c', itemId: 'borrado');
      for (var n = 0; n < 3; n++) {
        await review('c', now, grade: 'again');
      }
      await (h.db.update(h.db.knowledgeEntries)
            ..where((e) => e.id.equals('borrado')))
          .write(KnowledgeEntriesCompanion(deletedAt: Value(now)));
      expect(
        (await repository.current(const StudyScope.all())).hardestCards,
        isEmpty,
      );
    });

    test('cuenta toda la historia, no solo las últimas semanas', () async {
      await h.card('c');
      for (var n = 0; n < 3; n++) {
        await review('c', daysAgo(500), grade: 'again');
      }
      expect(
        (await repository.current(const StudyScope.all())).hardestCards,
        hasLength(1),
      );
    });
  });

  test('sigue al recorte: solo los repasos de sus tarjetas', () async {
    await insertItemRows(h.db, id: 'otro', title: 'Otro');
    await h.card('mia');
    await h.card('ajena', itemId: 'otro');
    for (var n = 0; n < 3; n++) {
      await review('mia', daysAgo(n), grade: 'again');
      await review('ajena', daysAgo(n));
    }
    final mine = await repository.current(const StudyScope.item('item'));
    expect(mine.retentionByWeek.last.total, 3);
    expect(mine.retentionByWeek.last.retained, 0);
    expect(mine.hardestCards.single.flashcardId, 'mia');
    final other = await repository.current(const StudyScope.item('otro'));
    expect(other.retentionByWeek.last.retained, 3);
    expect(other.hardestCards, isEmpty);
    expect(other.currentRun, 3);
  });

  test('vuelve a emitir sola cuando hay un repaso nuevo', () async {
    await h.card('c');
    final queue = StreamQueue(repository.watch(const StudyScope.all()));
    addTearDown(queue.cancel);

    expect((await queue.next).retentionByWeek.last.total, 0);
    await review('c', now);
    expect((await queue.next).retentionByWeek.last.total, 1);
  });
}
