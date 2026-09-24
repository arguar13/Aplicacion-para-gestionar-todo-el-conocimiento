import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/library_query_json.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';

class NotebookRepositoryImpl implements NotebookRepository {
  NotebookRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

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
  Future<void> delete(String id) async {
    await (_db.delete(_db.notebooks)..where((n) => n.id.equals(id))).go();
  }

  @override
  Future<void> addItem({
    required String notebookId,
    required String itemId,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.notebookItems)
          .insert(
            NotebookItemsCompanion.insert(
              notebookId: notebookId,
              itemId: itemId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
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
  Future<LibraryQuery> resolveQuery(String notebookId) async {
    final row = await (_db.select(
      _db.notebooks,
    )..where((n) => n.id.equals(notebookId))).getSingle();
    if (row.mode == NotebookMode.query) {
      return libraryQueryFromJson(
        jsonDecode(row.queryJson!) as Map<String, Object?>,
      );
    }
    final items = await (_db.select(
      _db.notebookItems,
    )..where((n) => n.notebookId.equals(notebookId))).get();
    return LibraryQuery(ids: {for (final i in items) i.itemId});
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
  );
}
