import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';

/// Los días con alguna actividad que cuenta para el hábito (F17, D6): los
/// cuatro orígenes que la racha y las insignias comparten —repasar
/// (`review_log`), editar una nota viva (`field_version`), extraer una
/// nota atómica (`item.created_at`) y triar la Bandeja o resolver algo en
/// Vocabulario (`habit_event`)—.
///
/// Cuenta el día histórico aunque el elemento se archive después —mismo
/// criterio que `review_log`/`habit_event`, que tampoco dejan de contar un
/// día por algo que pasó más tarde—; no filtra por activo a propósito.
class HabitActivityDays {
  const HabitActivityDays(this._db);

  final AppDatabase _db;

  Future<Set<DateTime>> all() async {
    return <DateTime>{
      ...await _reviewDays(),
      ...await _livingNoteEditDays(),
      ...await _atomicNoteCreationDays(),
      ...await _habitEventDays(),
    };
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
  /// edición, con un límite ya aceptado (una edición vieja del mismo
  /// campo, tapada por una más nueva, no deja rastro propio).
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
