import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/library_query_json.dart';
import 'package:sinapsis/features/library/domain/entities/saved_view.dart';
import 'package:sinapsis/features/library/domain/repositories/saved_view_repository.dart';

class SavedViewRepositoryImpl implements SavedViewRepository {
  SavedViewRepositoryImpl({
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
  Stream<List<SavedView>> watchAll() {
    return watchQuery(
      db: _db,
      tables: [_db.savedViews],
      read: () async {
        final rows = await (_db.select(
          _db.savedViews,
        )..orderBy([(v) => OrderingTerm(expression: v.position)])).get();
        return rows.map(_toEntity).toList();
      },
      telemetry: _telemetry,
      hint: 'SavedViewRepositoryImpl.watchAll',
    );
  }

  @override
  Future<SavedView> create({
    required String name,
    required LibraryQuery query,
    required LibraryViewMode viewMode,
  }) async {
    final nextPosition = await _nextPosition();
    final view = SavedView(
      id: _ids.next(),
      name: name,
      query: query,
      viewMode: viewMode,
      position: nextPosition,
      createdAt: _clock(),
    );
    await _db
        .into(_db.savedViews)
        .insert(
          SavedViewsCompanion.insert(
            id: view.id,
            name: view.name,
            queryJson: jsonEncode(libraryQueryToJson(view.query)),
            viewMode: view.viewMode,
            position: view.position,
            createdAt: view.createdAt,
          ),
        );
    return view;
  }

  Future<int> _nextPosition() async {
    final max = await (_db.selectOnly(
      _db.savedViews,
    )..addColumns([_db.savedViews.position.max()])).getSingle();
    final current = max.read(_db.savedViews.position.max());
    return current == null ? 0 : current + 1;
  }

  @override
  Future<void> rename(String id, String name) async {
    await (_db.update(_db.savedViews)..where((v) => v.id.equals(id))).write(
      SavedViewsCompanion(name: Value(name)),
    );
  }

  @override
  Future<void> setPinned(String id, {required bool pinned}) async {
    await (_db.update(_db.savedViews)..where((v) => v.id.equals(id))).write(
      SavedViewsCompanion(pinned: Value(pinned)),
    );
  }

  @override
  Future<void> reorder(List<String> ids) async {
    await _db.transaction(() async {
      for (final (position, id) in ids.indexed) {
        await (_db.update(_db.savedViews)..where((v) => v.id.equals(id))).write(
          SavedViewsCompanion(position: Value(position)),
        );
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.savedViews)..where((v) => v.id.equals(id))).go();
  }

  SavedView _toEntity(SavedViewRow row) => SavedView(
    id: row.id,
    name: row.name,
    query: libraryQueryFromJson(
      jsonDecode(row.queryJson) as Map<String, Object?>,
    ),
    viewMode: row.viewMode,
    position: row.position,
    pinned: row.pinned,
    createdAt: row.createdAt,
  );
}
