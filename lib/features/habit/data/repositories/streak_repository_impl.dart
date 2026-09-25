import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/habit/domain/entities/streak.dart';
import 'package:sinapsis/features/habit/domain/repositories/streak_repository.dart';
import 'package:sinapsis/features/habit/domain/services/streak_calculator.dart';

/// [StreakRepository] sobre la base (F17, D6): junta los cuatro orígenes de
/// «algo pasó, y cuándo» —repasar (`review_log`), editar una nota viva
/// (`field_version`), extraer una nota atómica (`item.created_at`) y triar
/// la Bandeja o resolver algo en Vocabulario (`habit_event`, commit 7a/7b)—
/// y deja el cálculo en sí a [calculateStreak], puro.
class StreakRepositoryImpl implements StreakRepository {
  const StreakRepositoryImpl({
    required AppDatabase database,
    required Clock clock,
  }) : _db = database,
       _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<Streak> current() async {
    final activeDays = <DateTime>{
      ...await _reviewDays(),
      ...await _livingNoteEditDays(),
      ...await _atomicNoteCreationDays(),
      ...await _habitEventDays(),
    };
    return calculateStreak(activeDays, today: _clock());
  }

  Future<Set<DateTime>> _reviewDays() async {
    final logs = _db.reviewLogs;
    final rows = await (_db.selectOnly(
      logs,
    )..addColumns([logs.reviewedAt])).get();
    return {for (final row in rows) row.read(logs.reviewedAt)!};
  }

  /// `field_version` no guarda historial, solo la última edición por campo
  /// —ver el doc comment de la tabla—: alcanza para saber si HOY hubo una
  /// edición, con el límite ya aceptado en la Decisión de este commit (una
  /// edición vieja del mismo campo, tapada por una más nueva, no deja
  /// rastro propio).
  Future<Set<DateTime>> _livingNoteEditDays() async {
    final fields = _db.fieldVersions;
    final notes = _db.knowledgeNotes;
    final rows =
        await (_db.selectOnly(fields)
              ..addColumns([fields.updatedAt])
              ..join([innerJoin(notes, notes.itemId.equalsExp(fields.itemId))])
              ..where(notes.noteKind.equalsValue(NoteKind.living)))
            .get();
    return {for (final row in rows) row.read(fields.updatedAt)!};
  }

  Future<Set<DateTime>> _atomicNoteCreationDays() async {
    final entries = _db.knowledgeEntries;
    final notes = _db.knowledgeNotes;
    final rows =
        await (_db.selectOnly(entries)
              ..addColumns([entries.createdAt])
              ..join([innerJoin(notes, notes.itemId.equalsExp(entries.id))])
              ..where(notes.noteKind.equalsValue(NoteKind.atomic)))
            .get();
    return {for (final row in rows) row.read(entries.createdAt)!};
  }

  Future<Set<DateTime>> _habitEventDays() async {
    final events = _db.habitEvents;
    final rows = await (_db.selectOnly(
      events,
    )..addColumns([events.occurredAt])).get();
    return {for (final row in rows) row.read(events.occurredAt)!};
  }
}
