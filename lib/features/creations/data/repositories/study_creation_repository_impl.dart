import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/creations/data/creation_files.dart';
import 'package:sinapsis/features/creations/data/repositories/study_creation_sql.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/repositories/study_creation_repository.dart';

/// [StudyCreationRepository] sobre `study_creations` (F43, v48).
class StudyCreationRepositoryImpl implements StudyCreationRepository {
  StudyCreationRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    IdGenerator ids = const UuidV7Generator(),
    Clock clock = DateTime.now,
    FileStore? files,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock,
       _files = files,
       _illustrations = files == null ? null : CreationIllustrationStore(files);

  final AppDatabase _db;
  final TelemetryService _telemetry;

  /// Donde viven los archivos de cada creación (sus ilustraciones), para
  /// borrarlos con ella; sin esto, borrar para siempre deja solo la fila.
  final FileStore? _files;

  /// Sus ilustraciones, para barrer las que el contenido ya no nombra cada
  /// vez que se guarda uno ([_sweep]); sin almacén, no se barre nada.
  final CreationIllustrationStore? _illustrations;
  final IdGenerator _ids;
  final Clock _clock;

  $StudyCreationsTable get _table => _db.studyCreations;

  // --- Leer ---------------------------------------------------------------

  @override
  Stream<List<StudyCreation>> watchByScope(CreationScope scope) => watchQuery(
    db: _db,
    tables: [_table],
    read: () => _byScope(scope),
    telemetry: _telemetry,
    hint: 'StudyCreationRepositoryImpl.watchByScope',
  );

  /// Las vivas de [scope], con la regla de [creationsInScopeSql].
  Future<List<StudyCreation>> _byScope(CreationScope scope) async {
    final filter = creationsInScopeSql(scope);
    final rows = await _db
        .customSelect(
          'SELECT * FROM study_creations c WHERE ${filter.sql} '
          'ORDER BY c.created_at DESC, c.id DESC',
          variables: filter.variables,
          readsFrom: {_table},
        )
        .asyncMap(_table.mapFromRow)
        .get();
    return _entities(rows);
  }

  @override
  Stream<StudyCreation?> watch(String id) => watchQuery(
    db: _db,
    tables: [_table],
    read: () async => _toEntity(await _row(id)),
    telemetry: _telemetry,
    hint: 'StudyCreationRepositoryImpl.watch',
  );

  @override
  Future<Either<Failure, StudyCreation?>> find(String id) =>
      _guard('find', () async => right(_toEntity(await _row(id))));

  @override
  Future<Either<Failure, List<StudyCreation>>> pending() =>
      _guard('pending', () async {
        final rows =
            await (_db.select(_table)
                  ..where(
                    (c) =>
                        c.deletedAt.isNull() &
                        c.status.isIn([
                          CreationStatus.queued.storageKey,
                          CreationStatus.generating.storageKey,
                        ]),
                  )
                  ..orderBy([
                    (c) => OrderingTerm.desc(c.runNow),
                    (c) => OrderingTerm.asc(c.createdAt),
                    (c) => OrderingTerm.asc(c.id),
                  ]))
                .get();
        return right(_entities(rows));
      });

  @override
  Stream<List<StudyCreation>> watchTrash() => watchQuery(
    db: _db,
    tables: [_table],
    read: () async => _entities(
      await (_db.select(_table)
            ..where((c) => c.deletedAt.isNotNull())
            ..orderBy([
              (c) => OrderingTerm.desc(c.deletedAt),
              (c) => OrderingTerm.desc(c.id),
            ]))
          .get(),
    ),
    telemetry: _telemetry,
    hint: 'StudyCreationRepositoryImpl.watchTrash',
  );

  // --- Crear y generar ------------------------------------------------------

  @override
  Future<Either<Failure, StudyCreation>> create(CreationRequest request) =>
      _guard('create', () async {
        final now = _clock();
        final id = _ids.next();
        // Las de extraer no esperan a nadie (decisión E): nacen listas, sin
        // contenido.
        final status = request.kind.isLiveView
            ? CreationStatus.ready
            : CreationStatus.queued;
        await _db
            .into(_table)
            .insert(
              StudyCreationsCompanion.insert(
                id: id,
                kind: request.kind.storageKey,
                scopeKind: request.scope.kindKey,
                scopeId: Value(request.scope.id),
                sourceIdsJson: Value(jsonEncode(request.sourceIds)),
                optionsJson: Value(jsonEncode(request.options)),
                languageCode: request.languageCode,
                status: status.storageKey,
                runNow: Value(request.runNow),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return right(_toEntity(await _row(id))!);
      });

  @override
  Future<Either<Failure, Unit>> markGenerating(
    String id, {
    required String? modelName,
  }) => _guard('markGenerating', () async {
    await _db.customUpdate(
      "UPDATE study_creations SET status = 'generating', progress = NULL, "
      "progress_step = 'preparing', attempts = attempts + 1, "
      'model_name = COALESCE(?, model_name) WHERE id = ?',
      variables: [Variable(modelName), Variable.withString(id)],
      updates: {_table},
    );
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> reportProgress(
    String id, {
    required double? progress,
    required CreationStep step,
  }) => _guard('reportProgress', () async {
    await (_db.update(_table)..where(
          (c) =>
              c.id.equals(id) &
              c.status.equals(CreationStatus.generating.storageKey),
        ))
        .write(
          StudyCreationsCompanion(
            progress: Value(progress?.clamp(0, 1).toDouble()),
            progressStep: Value(step.storageKey),
          ),
        );
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> complete(
    String id, {
    required String title,
    required String content,
    int contentVersion = 1,
    List<String>? sourceIds,
  }) => _guard('complete', () async {
    final trimmed = title.trim();
    await (_db.update(_table)..where((c) => c.id.equals(id))).write(
      StudyCreationsCompanion(
        title: Value(trimmed.isEmpty ? null : trimmed),
        contentJson: Value(content),
        contentVersion: Value(contentVersion),
        sourceIdsJson: sourceIds == null
            ? const Value.absent()
            : Value(jsonEncode(sourceIds)),
        status: Value(CreationStatus.ready.storageKey),
        failure: const Value(null),
        failureDetail: const Value(null),
        progress: const Value(null),
        progressStep: const Value(null),
        attempts: const Value(0),
        updatedAt: Value(_clock()),
      ),
    );
    await _sweep(id);
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> fail(
    String id,
    CreationFailure failure, {
    String? detail,
  }) => _guard('fail', () async {
    await (_db.update(_table)..where((c) => c.id.equals(id))).write(
      StudyCreationsCompanion(
        status: Value(CreationStatus.failed.storageKey),
        failure: Value(failure.storageKey),
        failureDetail: Value(detail),
        progress: const Value(null),
        progressStep: const Value(null),
        attempts: const Value(0),
        updatedAt: Value(_clock()),
      ),
    );
    return right(unit);
  });

  @override
  Future<Either<Failure, StudyCreation>> requeue(
    String id, {
    bool? runNow,
    Map<String, Object?>? options,
    List<String>? sourceIds,
    String? languageCode,
  }) => _guard('requeue', () async {
    final current = _toEntity(await _row(id));
    if (current == null) {
      return left(const Failure.validation(message: 'La creación no existe.'));
    }
    final status = current.kind.isLiveView
        ? CreationStatus.ready
        : CreationStatus.queued;
    await (_db.update(_table)..where((c) => c.id.equals(id))).write(
      StudyCreationsCompanion(
        status: Value(status.storageKey),
        failure: const Value(null),
        failureDetail: const Value(null),
        progress: const Value(null),
        progressStep: const Value(null),
        attempts: const Value(0),
        runNow: runNow == null ? const Value.absent() : Value(runNow),
        optionsJson: options == null
            ? const Value.absent()
            : Value(jsonEncode(options)),
        sourceIdsJson: sourceIds == null
            ? const Value.absent()
            : Value(jsonEncode(sourceIds)),
        languageCode: languageCode == null
            ? const Value.absent()
            : Value(languageCode),
        updatedAt: Value(_clock()),
      ),
    );
    return right(_toEntity(await _row(id))!);
  });

  @override
  Future<Either<Failure, int>> recoverInterrupted({
    required int maxAttempts,
    Set<String> inFlight = const {},
  }) => _guard('recoverInterrupted', () async {
    final generating = CreationStatus.generating.storageKey;
    return _db.transaction(() async {
      final rows = await (_db.select(
        _table,
      )..where((c) => c.status.equals(generating))).get();
      var requeued = 0;
      for (final row in rows) {
        if (inFlight.contains(row.id)) continue;
        if (row.attempts >= maxAttempts) {
          await (_db.update(_table)..where((c) => c.id.equals(row.id))).write(
            StudyCreationsCompanion(
              status: Value(CreationStatus.failed.storageKey),
              failure: Value(CreationFailure.interrupted.storageKey),
              failureDetail: Value(
                'Se empezó ${row.attempts} veces sin terminar.',
              ),
              progress: const Value(null),
              progressStep: const Value(null),
              updatedAt: Value(_clock()),
            ),
          );
          continue;
        }
        // Vuelve a la cola con sus intentos: el próximo `markGenerating` suma
        // uno más.
        await (_db.update(_table)..where((c) => c.id.equals(row.id))).write(
          StudyCreationsCompanion(
            status: Value(CreationStatus.queued.storageKey),
            progress: const Value(null),
            progressStep: const Value(null),
          ),
        );
        requeued++;
      }
      return right(requeued);
    });
  });

  // --- La persona -----------------------------------------------------------

  @override
  Future<Either<Failure, Unit>> rename(String id, String title) =>
      _guard('rename', () async {
        final trimmed = title.trim();
        if (trimmed.isEmpty) {
          return left(
            const Failure.validation(message: 'El título no puede ir vacío.'),
          );
        }
        await (_db.update(_table)..where((c) => c.id.equals(id))).write(
          StudyCreationsCompanion(
            title: Value(trimmed),
            updatedAt: Value(_clock()),
          ),
        );
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> amend(
    String id, {
    Map<String, Object?>? options,
    String? content,
  }) => _guard('amend', () async {
    if (options == null && content == null) return right(unit);
    // La fecha avanza: así un retoque viaja en la unión de bóvedas, que se
    // queda con la versión tocada más tarde (`StudyCreationsMerge`).
    final changed =
        await (_db.update(_table)..where(
              (c) =>
                  c.id.equals(id) &
                  c.status.equals(CreationStatus.ready.storageKey) &
                  c.deletedAt.isNull(),
            ))
            .write(
              StudyCreationsCompanion(
                optionsJson: options == null
                    ? const Value.absent()
                    : Value(jsonEncode(options)),
                contentJson: content == null
                    ? const Value.absent()
                    : Value(content),
                updatedAt: Value(_clock()),
              ),
            );
    if (changed == 0) {
      return left(
        const Failure.validation(message: 'La creación no está lista.'),
      );
    }
    if (content != null) await _sweep(id);
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> trash(String id) => _guard('trash', () async {
    final now = _clock();
    await (_db.update(
      _table,
    )..where((c) => c.id.equals(id) & c.deletedAt.isNull())).write(
      StudyCreationsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    return right(unit);
  });

  @override
  Future<Either<Failure, Unit>> restore(String id) =>
      _guard('restore', () async {
        final row = await _row(id);
        if (row == null || row.deletedAt == null) return right(unit);
        final pending = CreationStatus.fromStorageKey(row.status)?.isPending;
        await (_db.update(_table)..where((c) => c.id.equals(id))).write(
          StudyCreationsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(_clock()),
            // Lo que se borró a medias no se retoma solo al restaurarlo: la
            // persona lo había sacado de la cola, y decide si lo reintenta.
            status: pending ?? false
                ? Value(CreationStatus.failed.storageKey)
                : const Value.absent(),
            failure: pending ?? false
                ? Value(CreationFailure.interrupted.storageKey)
                : const Value.absent(),
            progress: const Value(null),
            progressStep: const Value(null),
          ),
        );
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> purge(List<String> ids) =>
      _guard('purge', () async {
        if (ids.isEmpty) return right(unit);
        await _purgeWhere((c) => c.id.isIn(ids) & c.deletedAt.isNotNull());
        return right(unit);
      });

  @override
  Future<Either<Failure, Unit>> emptyTrash() => _guard('emptyTrash', () async {
    await _purgeWhere((c) => c.deletedAt.isNotNull());
    return right(unit);
  });

  /// Borra para siempre las filas de [where] y, después, la carpeta de cada
  /// una en el almacén (`originales/<creación>/`): sus ilustraciones y lo que
  /// su tipo haya guardado, sea el que sea. Como en la biblioteca, las filas
  /// se van en una transacción y los archivos fuera de ella —el disco no es
  /// transaccional—: uno que se resiste se anota y no deshace el borrado.
  Future<void> _purgeWhere(
    Expression<bool> Function($StudyCreationsTable c) where,
  ) async {
    final purged = await _db.transaction(() async {
      final rows =
          await (_db.selectOnly(_table)
                ..addColumns([_table.id])
                ..where(where(_table)))
              .get();
      final ids = [for (final row in rows) row.read(_table.id)!];
      if (ids.isNotEmpty) {
        await (_db.delete(_table)..where((c) => c.id.isIn(ids))).go();
      }
      return ids;
    });
    final files = _files;
    if (files == null) return;
    for (final id in purged) {
      try {
        await files.deleteAllOf(id);
        // El disco puede fallar de muchas formas, y ninguna vuelve atrás un
        // borrado que la persona ya pidió y que en la base ya ocurrió.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        _telemetry.recordError(
          e,
          stackTrace,
          hint: 'StudyCreationRepositoryImpl.purge: quedaron archivos de $id',
        );
      }
    }
  }

  /// Lo que viene después de guardar un contenido de [id] —al generarla, al
  /// volver a generarla, al retocarla—, para todos los tipos por igual: se
  /// borran sus ilustraciones que el contenido guardado ya no nombra en
  /// ningún `illustration_ref` (`CreationIllustrationStore.sweep`).
  ///
  /// Siempre **después** de escribir la fila: si el guardado falla o se
  /// cancela antes, lo de antes sigue nombrado y queda. Lo que un ilustrador
  /// guardó y todavía no llegó al contenido no se toca. Un archivo que se
  /// resiste se anota y no deshace lo guardado.
  Future<void> _sweep(String id) async {
    final illustrations = _illustrations;
    if (illustrations == null) return;
    try {
      await illustrations.sweep(id, named: () => _namedFiles(id));
      // El disco puede fallar de muchas formas, y ninguna deshace un
      // contenido que ya quedó guardado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'StudyCreationRepositoryImpl.sweep: no se barrió $id',
      );
    }
  }

  /// Los archivos de [id] que su contenido guardado nombra, con la regla de
  /// la unión de bóvedas (`studyCreationFilesSql`); `null` si ya no está.
  Future<Set<String>?> _namedFiles(String id) async {
    if (await _row(id) == null) return null;
    final rows = await _db
        .customSelect(
          studyCreationFilesSql('main', oneCreation: true),
          variables: [Variable.withString(id)],
          readsFrom: {_table},
        )
        .get();
    return {for (final row in rows) row.read<String>('path')};
  }

  // --- Filas ----------------------------------------------------------------

  Future<StudyCreationRow?> _row(String id) =>
      (_db.select(_table)..where((c) => c.id.equals(id))).getSingleOrNull();

  List<StudyCreation> _entities(List<StudyCreationRow> rows) => [
    for (final row in rows) ?_toEntity(row),
  ];

  /// La entidad de [row], o `null` si su tipo, su estado o su recorte son de
  /// una versión que esta no conoce (llegó por la unión de bóvedas).
  StudyCreation? _toEntity(StudyCreationRow? row) {
    if (row == null) return null;
    final kind = StudyCreationKind.fromStorageKey(row.kind);
    final status = CreationStatus.fromStorageKey(row.status);
    final scope = CreationScope.fromParts(row.scopeKind, row.scopeId);
    if (kind == null || status == null || scope == null) return null;
    return StudyCreation(
      id: row.id,
      kind: kind,
      title: row.title,
      scope: scope,
      sourceIds: _stringList(row.sourceIdsJson),
      options: _object(row.optionsJson),
      content: row.contentJson,
      contentVersion: row.contentVersion,
      languageCode: row.languageCode,
      status: status,
      failure: row.failure == null
          ? null
          : CreationFailure.fromStorageKey(row.failure!),
      failureDetail: row.failureDetail,
      progress: row.progress,
      step: CreationStep.fromStorageKey(row.progressStep),
      runNow: row.runNow,
      attempts: row.attempts,
      modelName: row.modelName,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }

  static List<String> _stringList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final id in decoded)
          if (id is String) id,
      ];
    } on FormatException {
      return const [];
    }
  }

  static Map<String, Object?> _object(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  Future<Either<Failure, T>> _guard<T>(
    String name,
    Future<Either<Failure, T>> Function() body,
  ) async {
    try {
      return await body();
      // Un TypeError de una fila rara es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'StudyCreationRepositoryImpl.$name',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }
}
