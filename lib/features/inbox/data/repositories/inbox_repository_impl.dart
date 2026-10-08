import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/text_presence.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/inbox/domain/entities/inbox_standing.dart';
import 'package:sinapsis/features/inbox/domain/entities/note_reference.dart';
import 'package:sinapsis/features/inbox/domain/entities/pending_source.dart';
import 'package:sinapsis/features/inbox/domain/repositories/inbox_repository.dart';

class InboxRepositoryImpl implements InboxRepository {
  const InboxRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  /// Quien escribe el estado, el subtipo y la madurez: ver
  /// [KnowledgeEntryWriter].
  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  /// Lo que espera en la Bandeja: una fuente en `processed`, fuera de la
  /// papelera y que ya tiene texto (F30, decisión 68). Un solo criterio para
  /// el mazo, la lista de la cola, la insignia y el contador: lo que todavía
  /// no tiene texto —un audio sin transcribir— sigue en la Biblioteca y entra
  /// solo cuando lo tenga. Ver [hasTextSql].
  Expression<bool> _isPending($KnowledgeEntriesTable e) =>
      e.kind.equalsValue(ItemKind.source) &
      e.state.equalsValue(ItemState.processed) &
      e.isActive &
      CustomExpression<bool>(hasTextSql('item'));

  @override
  Stream<List<String>> watchPendingIds() {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries, _db.renditions],
      read: () async {
        final rows =
            await (_db.select(_db.knowledgeEntries)
                  ..where(_isPending)
                  ..orderBy([(e) => OrderingTerm(expression: e.updatedAt)]))
                .get();
        return rows.map((row) => row.id).toList();
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPendingIds',
    );
  }

  @override
  Stream<List<PendingSource>> watchPending() {
    final entries = _db.knowledgeEntries;
    final sources = _db.knowledgeSources;
    return watchQuery(
      db: _db,
      tables: [entries, sources, _db.renditions],
      read: () async {
        // Un `innerJoin`: una fuente siempre tiene su fila de `source` —la
        // escriben juntas `save()` y el espejo—, y sin ella no habría tipo
        // ni fecha que mostrar.
        final rows =
            await (_db.select(entries).join([
                    innerJoin(sources, sources.itemId.equalsExp(entries.id)),
                  ])
                  ..where(_isPending(entries))
                  ..orderBy([OrderingTerm(expression: entries.updatedAt)]))
                .get();
        return [
          for (final row in rows)
            PendingSource(
              id: row.readTable(entries).id,
              title: row.readTable(entries).title,
              kind: row.readTable(sources).sourceType,
              capturedAt: row.readTable(sources).capturedAt,
            ),
        ];
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchPending',
    );
  }

  @override
  Stream<InboxStanding?> watchStanding(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeEntries, _db.fieldVersions, _db.renditions],
      read: () async {
        final entry = await (_db.select(
          _db.knowledgeEntries,
        )..where((e) => e.id.equals(itemId) & e.isActive)).getSingleOrNull();
        if (entry == null) return null;
        final status = InboxStatus.of(entry.kind, entry.state);
        if (status == null) return null;

        // Si ya tiene texto (F30, decisión 68): lo que todavía no lo tiene no
        // está en la Bandeja —no se cuenta ni se muestra—, y lo que ya se
        // trió no puede volver a ella.
        final hasText =
            (await _db
                    .customSelect(
                      'SELECT ${hasTextSql('item')} AS has_text FROM item '
                      'WHERE item.id = ?',
                      variables: [Variable.withString(itemId)],
                      readsFrom: {_db.knowledgeEntries, _db.renditions},
                    )
                    .getSingle())
                .read<bool>('has_text');
        if (status == InboxStatus.pending && !hasText) return null;

        // Desde cuándo: la última vez que se cambió el estado, que ya
        // registra la versión por campo (F11) —ver [InboxStanding.since]—.
        final version =
            await (_db.select(_db.fieldVersions)..where(
                  (f) =>
                      f.itemId.equals(itemId) &
                      f.fieldName.equals(EntryField.state),
                ))
                .getSingleOrNull();
        return InboxStanding(
          status: status,
          since: version?.updatedAt,
          hasText: hasText,
        );
      },
      telemetry: _telemetry,
      hint: 'InboxRepositoryImpl.watchStanding',
    );
  }

  @override
  Future<Either<Failure, Unit>> transitionState({
    required String itemId,
    required ItemState to,
  }) async {
    try {
      if (!await _writer.setState(itemId, to)) {
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
                  _db.knowledgeNotes.noteKind.equalsValue(NoteKind.living) &
                  _db.knowledgeEntries.isActive,
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
      if (!await _writer.setMaturity(itemId, maturity)) {
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
      if (!await _writer.setNoteKind(itemId, kind)) {
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
