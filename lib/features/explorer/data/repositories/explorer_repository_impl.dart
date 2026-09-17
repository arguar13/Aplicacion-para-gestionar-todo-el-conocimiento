import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/explorer/domain/entities/folder.dart';
import 'package:sinapsis/features/explorer/domain/repositories/explorer_repository.dart';

class ExplorerRepositoryImpl implements ExplorerRepository {
  const ExplorerRepositoryImpl({
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
  Stream<List<Folder>> watchAllFolders() {
    return watchQuery(
      db: _db,
      tables: [_db.folders],
      read: () async {
        final rows = await (_db.select(
          _db.folders,
        )..orderBy([(f) => OrderingTerm(expression: f.name)])).get();
        return rows.map(_toFolder).toList();
      },
      telemetry: _telemetry,
      hint: 'ExplorerRepositoryImpl.watchAllFolders',
    );
  }

  @override
  Future<Either<Failure, Folder>> createFolder({
    required String name,
    required String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final clash =
          await (_db.select(_db.folders)..where(
                (f) =>
                    f.name.lower().equals(trimmed.toLowerCase()) &
                    (parentId == null
                        ? f.parentId.isNull()
                        : f.parentId.equals(parentId)),
              ))
              .getSingleOrNull();
      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe una carpeta "$trimmed".'),
        );
      }

      final folder = Folder(
        id: _ids.next(),
        name: trimmed,
        parentId: parentId,
        createdAt: _clock(),
      );
      await _db
          .into(_db.folders)
          .insert(
            FoldersCompanion.insert(
              id: folder.id,
              name: folder.name,
              parentId: Value(folder.parentId),
              createdAt: folder.createdAt,
            ),
          );

      return right(folder);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'ExplorerRepositoryImpl.createFolder'),
      );
    }
  }

  @override
  Future<Either<Failure, Folder>> renameFolder({
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return left(
        const Failure.validation(message: 'El nombre no puede quedar vacío.'),
      );
    }

    try {
      final current = await (_db.select(
        _db.folders,
      )..where((f) => f.id.equals(id))).getSingleOrNull();
      if (current == null) {
        return left(
          const Failure.unexpected(
            message: 'La carpeta ya no existe; puede que se haya borrado.',
          ),
        );
      }

      final clash =
          await (_db.select(_db.folders)..where(
                (f) =>
                    f.name.lower().equals(trimmed.toLowerCase()) &
                    f.id.equals(id).not() &
                    (current.parentId == null
                        ? f.parentId.isNull()
                        : f.parentId.equals(current.parentId!)),
              ))
              .getSingleOrNull();
      if (clash != null) {
        return left(
          Failure.validation(message: 'Ya existe una carpeta "$trimmed".'),
        );
      }

      final updated =
          await (_db.update(_db.folders)..where((f) => f.id.equals(id)))
              .writeReturning(FoldersCompanion(name: Value(trimmed)));

      final row = updated.singleOrNull;
      if (row == null) {
        return left(
          const Failure.unexpected(
            message: 'La carpeta ya no existe; puede que se haya borrado.',
          ),
        );
      }

      return right(_toFolder(row));
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'ExplorerRepositoryImpl.renameFolder'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteFolder(String id) async {
    try {
      await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'ExplorerRepositoryImpl.deleteFolder'),
      );
    }
  }

  @override
  Stream<Set<String>> watchItemIdsInFolder(String? folderId) {
    return watchQuery(
      db: _db,
      tables: [_db.items, _db.itemFolders],
      read: () async {
        if (folderId == null) {
          final rows =
              await (_db.select(_db.items)..where(
                    (i) => i.id
                        .isInQuery(
                          _db.selectOnly(_db.itemFolders)
                            ..addColumns([_db.itemFolders.itemId]),
                        )
                        .not(),
                  ))
                  .get();
          return rows.map((r) => r.id).toSet();
        }

        final rows = await (_db.select(
          _db.itemFolders,
        )..where((it) => it.folderId.equals(folderId))).get();
        return rows.map((r) => r.itemId).toSet();
      },
      telemetry: _telemetry,
      hint: 'ExplorerRepositoryImpl.watchItemIdsInFolder',
    );
  }

  @override
  Stream<Set<String>> watchFolderIdsForItem(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.itemFolders],
      read: () async {
        final rows = await (_db.select(
          _db.itemFolders,
        )..where((it) => it.itemId.equals(itemId))).get();
        return rows.map((r) => r.folderId).toSet();
      },
      telemetry: _telemetry,
      hint: 'ExplorerRepositoryImpl.watchFolderIdsForItem',
    );
  }

  @override
  Future<Either<Failure, Unit>> addItemToFolder({
    required String itemId,
    required String folderId,
  }) async {
    try {
      await _db
          .into(_db.itemFolders)
          .insertOnConflictUpdate(
            ItemFoldersCompanion.insert(itemId: itemId, folderId: folderId),
          );
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(e, stackTrace, 'ExplorerRepositoryImpl.addItemToFolder'),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> removeItemFromFolder({
    required String itemId,
    required String folderId,
  }) async {
    try {
      await (_db.delete(_db.itemFolders)..where(
            (it) => it.itemId.equals(itemId) & it.folderId.equals(folderId),
          ))
          .go();
      return right(unit);
      // Ver `_unexpected`: un TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      return left(
        _unexpected(
          e,
          stackTrace,
          'ExplorerRepositoryImpl.removeItemFromFolder',
        ),
      );
    }
  }

  Folder _toFolder(FolderRow row) => Folder(
    id: row.id,
    name: row.name,
    parentId: row.parentId,
    createdAt: row.createdAt,
  );

  Failure _unexpected(Object e, StackTrace stackTrace, String hint) {
    _telemetry.recordError(e, stackTrace, hint: hint);
    return Failure.unexpected(message: e.toString());
  }
}
