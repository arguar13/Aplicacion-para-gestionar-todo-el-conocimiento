import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/processed_entries.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/library_query_json.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_scope.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';

/// [NotebookRepository] sobre la base. Lo que tiene un cuaderno lo responde
/// «Procesado» ([ProcessedRepository.matchingIds]): un solo motor para «qué
/// procesados cumplen esto», el mismo de la pantalla Procesado.
class NotebookRepositoryImpl implements NotebookRepository {
  NotebookRepositoryImpl({
    required AppDatabase database,
    required ProcessedRepository processed,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _processed = processed,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final ProcessedRepository _processed;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  /// Cuántos ids entran en una sola consulta: por debajo del tope de
  /// parámetros de SQLite.
  static const _idsPerQuery = 400;

  @override
  Stream<List<Notebook>> watchAll() {
    return watchQuery(
      db: _db,
      tables: [_db.notebooks],
      read: () async {
        final rows = await (_db.select(
          _db.notebooks,
        )..orderBy([(n) => OrderingTerm(expression: n.createdAt)])).get();
        return rows.map(_toEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'NotebookRepositoryImpl.watchAll',
    );
  }

  @override
  Stream<Notebook?> watchById(String id) {
    return watchQuery(
      db: _db,
      tables: [_db.notebooks],
      read: () async {
        final row = await (_db.select(
          _db.notebooks,
        )..where((n) => n.id.equals(id))).getSingleOrNull();
        return row == null ? null : _toEntity(row);
      },
      telemetry: _telemetry,
      hint: 'NotebookRepositoryImpl.watchById',
    );
  }

  @override
  Stream<Set<String>> watchItemIds(String notebookId) {
    return watchQuery(
      db: _db,
      tables: [_db.notebookItems],
      read: () async {
        final items = await (_db.select(
          _db.notebookItems,
        )..where((n) => n.notebookId.equals(notebookId))).get();
        return {for (final i in items) i.itemId};
      },
      telemetry: _telemetry,
      hint: 'NotebookRepositoryImpl.watchItemIds',
    );
  }

  @override
  Future<Notebook> create({
    required String name,
    required NotebookMode mode,
    LibraryQuery? query,
  }) async {
    assert(
      mode != NotebookMode.query || query != null,
      'un cuaderno por consulta necesita una consulta',
    );
    final now = _clock();
    final notebook = Notebook(
      id: _ids.next(),
      name: name,
      mode: mode,
      query: mode == NotebookMode.query ? query : null,
      createdAt: now,
      updatedAt: now,
    );
    await _db
        .into(_db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: notebook.id,
            name: notebook.name,
            mode: notebook.mode,
            queryJson: Value(
              notebook.query == null
                  ? null
                  : jsonEncode(libraryQueryToJson(notebook.query!)),
            ),
            createdAt: notebook.createdAt,
            updatedAt: notebook.updatedAt,
          ),
        );
    return notebook;
  }

  @override
  Future<void> rename({required String id, required String name}) async {
    await (_db.update(_db.notebooks)..where((n) => n.id.equals(id))).write(
      NotebooksCompanion(name: Value(name), updatedAt: Value(_clock())),
    );
  }

  @override
  Future<void> dismissEmptiedNotice(String id) async {
    await (_db.update(_db.notebooks)..where((n) => n.id.equals(id))).write(
      const NotebooksCompanion(emptiedForProcessedAt: Value(null)),
    );
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.notebooks)..where((n) => n.id.equals(id))).go();
  }

  @override
  Future<void> addItem({required String notebookId, required String itemId}) =>
      addItems(notebookId: notebookId, itemIds: [itemId]);

  @override
  Future<void> addItems({
    required String notebookId,
    required Iterable<String> itemIds,
  }) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      // La regla (F41, paso 5): de lo pedido, entra solo lo que es un
      // documento procesado vivo —uno en la papelera no se ofrece, y no
      // entraría a la vista—. La misma consulta inserta y filtra, así que
      // nada puede colarse entre mirar y escribir.
      for (var start = 0; start < ids.length; start += _idsPerQuery) {
        final slice = ids.skip(start).take(_idsPerQuery).toList();
        await _db.customInsert(
          'INSERT OR IGNORE INTO notebook_item (notebook_id, item_id) '
          'SELECT ?, item.id FROM item '
          'WHERE item.id IN (${List.filled(slice.length, '?').join(', ')}) '
          'AND $kActiveItemSql AND ${isProcessedSql('item.id')}',
          variables: [
            Variable.withString(notebookId),
            for (final id in slice) Variable.withString(id),
          ],
          updates: {_db.notebookItems},
        );
      }
      await _touch(notebookId);
    });
  }

  @override
  Future<void> removeItem({
    required String notebookId,
    required String itemId,
  }) async {
    await _db.transaction(() async {
      await (_db.delete(_db.notebookItems)..where(
            (n) => n.notebookId.equals(notebookId) & n.itemId.equals(itemId),
          ))
          .go();
      await _touch(notebookId);
    });
  }

  Future<void> _touch(String notebookId) async {
    await (_db.update(_db.notebooks)..where((n) => n.id.equals(notebookId)))
        .write(NotebooksCompanion(updatedAt: Value(_clock())));
  }

  @override
  Future<ProcessedQuery> resolveQuery(String notebookId) async {
    final row = await (_db.select(
      _db.notebooks,
    )..where((n) => n.id.equals(notebookId))).getSingle();
    return _queryOf(row);
  }

  @override
  Future<List<({String id, String name, ProcessedQuery query})>>
  resolveAllQueries() async {
    final rows = await _db.select(_db.notebooks).get();
    final members = <String, Set<String>>{};
    for (final item in await _db.select(_db.notebookItems).get()) {
      (members[item.notebookId] ??= {}).add(item.itemId);
    }
    return [
      for (final row in rows)
        (
          id: row.id,
          name: row.name,
          query: _queryWith(row, members[row.id] ?? const {}),
        ),
    ];
  }

  Future<ProcessedQuery> _queryOf(NotebookRow row) async {
    if (row.mode == NotebookMode.query) return _queryWith(row, const {});
    final items = await (_db.select(
      _db.notebookItems,
    )..where((n) => n.notebookId.equals(row.id))).get();
    return _queryWith(row, {for (final i in items) i.itemId});
  }

  /// La consulta de [row]: su vista guardada, o [members] si es a mano.
  ProcessedQuery _queryWith(NotebookRow row, Set<String> members) =>
      row.mode == NotebookMode.query
      ? processedQueryForView(
          libraryQueryFromJson(
            jsonDecode(row.queryJson!) as Map<String, Object?>,
          ),
        )
      : processedQueryForMembers(members);

  @override
  Future<Either<Failure, List<String>>> memberIds(String notebookId) async {
    final row = await (_db.select(
      _db.notebooks,
    )..where((n) => n.id.equals(notebookId))).getSingleOrNull();
    if (row == null) {
      // Un alcance que apunta a un cuaderno borrado no tiene nada adentro, y
      // se dice.
      return left(
        const Failure.unexpected(
          message: 'El cuaderno ya no existe; puede que se haya borrado.',
        ),
      );
    }
    return _processed.matchingIds(await _queryOf(row));
  }

  Notebook _toEntity(NotebookRow row) => Notebook(
    id: row.id,
    name: row.name,
    mode: row.mode,
    query: row.queryJson == null
        ? null
        : libraryQueryFromJson(
            jsonDecode(row.queryJson!) as Map<String, Object?>,
          ),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    emptiedForProcessedAt: row.emptiedForProcessedAt,
  );
}
