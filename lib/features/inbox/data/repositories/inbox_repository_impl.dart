import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';

class InboxRepositoryImpl implements InboxRepository {
  const InboxRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Stream<List<String>> watchPendingIds() {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries],
      read: () async {
        final rows =
            await (_db.select(_db.knowledgeEntries)
                  ..where(
                    (e) =>
                        e.kind.equalsValue(ItemKind.source) &
                        e.state.equalsValue(ItemState.processed),
                  )
                  ..orderBy([(e) => OrderingTerm(expression: e.updatedAt)]))
                .get();
        return rows.map((row) => row.id).toList();
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPendingIds',
    );
  }

  @override
  Future<Either<Failure, Unit>> transitionState({
    required String itemId,
    required ItemState to,
  }) async {
    try {
      final updated =
          await (_db.update(_db.knowledgeEntries)
                ..where((e) => e.id.equals(itemId)))
              .writeReturning(KnowledgeEntriesCompanion(state: Value(to)));

      if (updated.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'El elemento ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.transitionState'),
      );
    }
  }

  @override
  Stream<List<NoteReference>> watchLivingNotes({String? searchText}) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries, _db.knowledgeNotes],
      read: () async {
        final trimmed = searchText?.trim();

        final query =
            _db.select(_db.knowledgeEntries).join([
              innerJoin(
                _db.knowledgeNotes,
                _db.knowledgeNotes.itemId.equalsExp(_db.knowledgeEntries.id),
              ),
            ])..where(
              _db.knowledgeEntries.kind.equalsValue(ItemKind.note) &
                  _db.knowledgeNotes.noteKind.equalsValue(NoteKind.living),
            );

        if (trimmed != null && trimmed.isNotEmpty) {
          query.where(
            _db.knowledgeEntries.title.lower().contains(trimmed.toLowerCase()),
          );
        }

        query.orderBy([OrderingTerm(expression: _db.knowledgeEntries.title)]);

        final rows = await query.get();
        return rows.map((row) {
          final entry = row.readTable(_db.knowledgeEntries);
          return NoteReference(
            id: entry.id,
            title: entry.title,
            subtitle: entry.subtitle,
          );
        }).toList();
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchLivingNotes',
    );
  }

  @override
  Stream<NoteMaturity?> watchNoteMaturity(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeNotes],
      read: () async {
        final row = await (_db.select(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
        return row?.maturity;
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchNoteMaturity',
    );
  }

  @override
  Stream<NoteKind?> watchNoteKind(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeNotes],
      read: () async {
        final row = await (_db.select(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
        return row?.noteKind;
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchNoteKind',
    );
  }

  @override
  Future<Either<Failure, Unit>> setNoteMaturity({
    required String itemId,
    required NoteMaturity maturity,
  }) async {
    try {
      final updated =
          await (_db.update(
            _db.knowledgeNotes,
          )..where((n) => n.itemId.equals(itemId))).writeReturning(
            KnowledgeNotesCompanion(maturity: Value(maturity)),
          );

      if (updated.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'La nota ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.setNoteMaturity'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> setNoteKind({
    required String itemId,
    required NoteKind kind,
  }) async {
    try {
      final updated =
          await (_db.update(_db.knowledgeNotes)
                ..where((n) => n.itemId.equals(itemId)))
              .writeReturning(KnowledgeNotesCompanion(noteKind: Value(kind)));

      if (updated.isEmpty) {
        return left(
          const Failure.unexpected(
            message: 'La nota ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'InboxRepositoryImpl.setNoteKind'),
      );
    }
  }

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
