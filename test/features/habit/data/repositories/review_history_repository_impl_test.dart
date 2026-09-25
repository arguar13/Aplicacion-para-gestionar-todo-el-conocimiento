import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/habit/data/repositories/review_history_repository_impl.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// [ReviewHistoryRepositoryImpl] contra SQLite real (F17, D8).
void main() {
  late AppDatabase db;
  final today = DateTime(2026, 9, 25, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
  });

  tearDown(() => db.close());

  ReviewHistoryRepositoryImpl repository({DateTime? now}) =>
      ReviewHistoryRepositoryImpl(
        database: db,
        telemetry: MockTelemetryService(),
        clock: () => now ?? today,
      );

  Future<String> seedCard({DateTime? deletedAt, String front = 'p'}) async {
    final itemId = 'item-${counter++}';
    final cardId = 'tarjeta-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: 'Nota $itemId',
            kind: ItemKind.note,
            state: ItemState.captured,
            createdAt: today,
            updatedAt: today,
            deviceId: 'dispositivo',
            deletedAt: Value(deletedAt),
          ),
        );
    await db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: cardId,
            itemId: itemId,
            front: front,
            back: 'r',
            dueAt: today,
            createdAt: today,
          ),
        );
    return cardId;
  }

  Future<void> addReview(String cardId, DateTime at, String grade) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: 'rev-${counter++}',
          flashcardId: cardId,
          reviewedAt: at,
          grade: grade,
          quality: grade == 'again' ? 0 : 4,
          intervalBefore: 1,
          intervalAfter: 3,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: 'dispositivo',
        ),
      );

  test('sin nada en review_log, las tres piezas vienen vacías', () async {
    final history = await repository().current();

    expect(history.retentionByWeek, hasLength(12));
    expect(history.retentionByWeek.every((w) => w.total == 0), isTrue);
    expect(history.activityByDay, hasLength(84));
    expect(history.activityByDay.every((d) => d.count == 0), isTrue);
    expect(history.hardestCards, isEmpty);
  });

  group('curva de retención y calendario de constancia', () {
    test('un repaso "good" hoy cuenta como retenido en la semana y en el '
        'día de hoy', () async {
      final card = await seedCard();
      await addReview(card, today, 'good');

      final history = await repository().current();

      expect(history.retentionByWeek.last.total, 1);
      expect(history.retentionByWeek.last.retained, 1);
      expect(history.activityByDay.last.count, 1);
    });

    test('"easy" también retiene; "again" y "hard" no', () async {
      final card = await seedCard();
      await addReview(card, today, 'easy');
      await addReview(card, today, 'again');
      await addReview(card, today, 'hard');

      final history = await repository().current();

      expect(history.retentionByWeek.last.total, 3);
      expect(history.retentionByWeek.last.retained, 1);
    });

    test('un repaso muy viejo, fuera de la ventana, no cuenta', () async {
      final card = await seedCard();
      await addReview(card, today.subtract(const Duration(days: 200)), 'good');

      final history = await repository().current();

      expect(history.retentionByWeek.every((w) => w.total == 0), isTrue);
      expect(history.activityByDay.every((d) => d.count == 0), isTrue);
    });
  });

  group('tarjetas difíciles', () {
    test('por debajo del piso de repasos, no aparece', () async {
      final card = await seedCard();
      await addReview(card, today, 'again');
      await addReview(card, today, 'again');

      final history = await repository().current();

      expect(history.hardestCards, isEmpty);
    });

    test(
      'con el piso alcanzado, aparece con su proporción de "again"',
      () async {
        final card = await seedCard(front: '¿La más difícil?');
        await addReview(card, today, 'again');
        await addReview(card, today, 'again');
        await addReview(card, today, 'good');

        final history = await repository().current();

        expect(history.hardestCards, hasLength(1));
        final hardest = history.hardestCards.single;
        expect(hardest.flashcardId, card);
        expect(hardest.front, '¿La más difícil?');
        expect(hardest.total, 3);
        expect(hardest.againCount, 2);
      },
    );

    test('la más difícil primero', () async {
      final facil = await seedCard(front: 'Fácil');
      for (var i = 0; i < 3; i++) {
        await addReview(facil, today, 'good');
      }
      final dificil = await seedCard(front: 'Difícil');
      await addReview(dificil, today, 'again');
      await addReview(dificil, today, 'again');
      await addReview(dificil, today, 'good');

      final history = await repository().current();

      expect(history.hardestCards.first.flashcardId, dificil);
      expect(history.hardestCards.last.flashcardId, facil);
    });

    test('una tarjeta de un elemento en la papelera no aparece', () async {
      final card = await seedCard(deletedAt: today);
      await addReview(card, today, 'again');
      await addReview(card, today, 'again');
      await addReview(card, today, 'again');

      final history = await repository().current();

      expect(history.hardestCards, isEmpty);
    });

    test('no depende de la ventana de las últimas semanas: cuenta toda la '
        'historia', () async {
      final card = await seedCard();
      await addReview(card, today.subtract(const Duration(days: 200)), 'again');
      await addReview(card, today.subtract(const Duration(days: 200)), 'again');
      await addReview(card, today.subtract(const Duration(days: 200)), 'again');

      final history = await repository().current();

      expect(history.hardestCards, hasLength(1));
    });
  });

  group('watch (F17, D8)', () {
    test('vuelve a emitir sola cuando hay un repaso nuevo', () async {
      final card = await seedCard();
      final queue = StreamQueue(repository().watch());
      addTearDown(queue.cancel);

      final first = await queue.next;
      expect(first.retentionByWeek.last.total, 0);

      await addReview(card, today, 'good');

      final second = await queue.next;
      expect(second.retentionByWeek.last.total, 1);
    });
  });
}
