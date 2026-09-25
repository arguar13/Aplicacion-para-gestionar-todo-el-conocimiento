import 'package:async/async.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/habit/data/repositories/streak_repository_impl.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Los cuatro orígenes de la racha (F17, D6), contra SQLite real: que cada
/// uno de verdad cuente un día, y que uniéndolos no se pierda ni se
/// duplique nada.
void main() {
  late AppDatabase db;
  final today = DateTime(2026, 9, 25, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    counter = 0;
  });

  tearDown(() => db.close());

  StreakRepositoryImpl repository({DateTime? now}) => StreakRepositoryImpl(
    database: db,
    telemetry: MockTelemetryService(),
    clock: () => now ?? today,
  );

  /// Un elemento nota, con su fila `note` —`kind` decide si cuenta como
  /// «extraer una nota atómica» o «editar una nota viva».
  Future<String> seedNote(NoteKind kind, {DateTime? createdAt}) async {
    final id = 'nota-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: id,
            title: 'Nota $id',
            kind: ItemKind.note,
            state: ItemState.captured,
            createdAt: createdAt ?? today,
            updatedAt: createdAt ?? today,
            deviceId: 'dispositivo',
          ),
        );
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: id,
            noteKind: kind,
            maturity: NoteMaturity.seed,
          ),
        );
    return id;
  }

  Future<void> editField(String itemId, DateTime at) => db
      .into(db.fieldVersions)
      .insertOnConflictUpdate(
        FieldVersionsCompanion.insert(
          itemId: itemId,
          fieldName: 'title',
          updatedAt: at,
          deviceId: 'dispositivo',
        ),
      );

  Future<void> addReview(DateTime at) async {
    final cardId = 'tarjeta-${counter++}';
    final itemId = await seedNote(NoteKind.living);
    await db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: cardId,
            itemId: itemId,
            front: 'p',
            back: 'r',
            dueAt: today,
            createdAt: today,
          ),
        );
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            id: 'rev-${counter++}',
            flashcardId: cardId,
            reviewedAt: at,
            grade: 'good',
            quality: 4,
            intervalBefore: 1,
            intervalAfter: 3,
            easeBefore: 2.5,
            easeAfter: 2.5,
            deviceId: 'dispositivo',
          ),
        );
  }

  Future<void> addHabitEvent(HabitEventKind kind, DateTime at) => db
      .into(db.habitEvents)
      .insert(
        HabitEventsCompanion.insert(
          id: 'ev-${counter++}',
          kind: kind,
          occurredAt: at,
        ),
      );

  test('sin nada en ninguna tabla, la racha es cero', () async {
    final streak = await repository().current();

    expect(streak.days, 0);
    expect(streak.activeToday, isFalse);
  });

  test('repasar una tarjeta hoy cuenta', () async {
    await addReview(today);

    final streak = await repository().current();

    expect(streak.activeToday, isTrue);
  });

  test('editar una nota viva hoy cuenta', () async {
    final id = await seedNote(NoteKind.living);
    await editField(id, today);

    final streak = await repository().current();

    expect(streak.activeToday, isTrue);
  });

  test('editar una nota ATÓMICA no cuenta como editar una nota viva', () async {
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    // Nace hace tres días —no hoy—, para que la creación en sí no sea lo
    // que hace que hoy cuente.
    final id = await seedNote(NoteKind.atomic, createdAt: threeDaysAgo);
    await editField(id, today);

    final streak = await repository().current();

    // El camino de «editar una nota viva» filtra por `note_kind =
    // 'living'`: una atómica no entra ahí, y no hay ningún otro camino
    // que la haga contar por editarla.
    expect(streak.activeToday, isFalse);
  });

  test('extraer una nota atómica hoy cuenta', () async {
    await seedNote(NoteKind.atomic, createdAt: today);

    final streak = await repository().current();

    expect(streak.activeToday, isTrue);
  });

  test('crear una nota VIVA no cuenta como extraer una atómica', () async {
    final yesterday = today.subtract(const Duration(days: 1));
    // Nace ayer, sin tocarla hoy: no hay ni creación atómica ni edición.
    await seedNote(NoteKind.living, createdAt: yesterday);

    final streak = await repository().current();

    expect(streak.activeToday, isFalse);
  });

  test('triar la Bandeja hoy cuenta', () async {
    await addHabitEvent(HabitEventKind.triage, today);

    final streak = await repository().current();

    expect(streak.activeToday, isTrue);
  });

  test('resolver algo en Vocabulario hoy cuenta', () async {
    await addHabitEvent(HabitEventKind.vocabulary, today);

    final streak = await repository().current();

    expect(streak.activeToday, isTrue);
  });

  test('varias acciones el mismo día no duplican el día', () async {
    await addHabitEvent(HabitEventKind.triage, today);
    await addHabitEvent(HabitEventKind.vocabulary, today);
    await addReview(today);

    final streak = await repository().current();

    expect(streak.days, 1);
  });

  test('acciones de días distintos arman una racha de verdad', () async {
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await addHabitEvent(HabitEventKind.triage, today);
    final livingId = await seedNote(NoteKind.living, createdAt: twoDaysAgo);
    await editField(livingId, yesterday);
    await seedNote(NoteKind.atomic, createdAt: twoDaysAgo);

    final streak = await repository().current();

    expect(streak.days, 3);
    expect(streak.activeToday, isTrue);
  });

  group('watch (F17, commit 8)', () {
    test('emite la racha de entrada', () async {
      await addHabitEvent(HabitEventKind.triage, today);
      final queue = StreamQueue(repository().watch());
      addTearDown(queue.cancel);

      final streak = await queue.next;

      expect(streak.activeToday, isTrue);
    });

    test('vuelve a emitir sola cuando se guarda un evento nuevo', () async {
      final queue = StreamQueue(repository().watch());
      addTearDown(queue.cancel);
      final first = await queue.next;
      expect(first.activeToday, isFalse);

      await addHabitEvent(HabitEventKind.vocabulary, today);

      final second = await queue.next;
      expect(second.activeToday, isTrue);
    });

    test('vuelve a emitir cuando se edita una nota viva', () async {
      final id = await seedNote(NoteKind.living);
      final queue = StreamQueue(repository().watch());
      addTearDown(queue.cancel);
      final first = await queue.next;
      expect(first.activeToday, isFalse);

      await editField(id, today);

      final second = await queue.next;
      expect(second.activeToday, isTrue);
    });
  });
}
