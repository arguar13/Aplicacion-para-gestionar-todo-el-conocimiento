import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';

/// [ProcessingStateRepository] sobre las columnas de procesamiento de
/// `source` —`processing_status`, `processing_error` y
/// `processing_attempts`— y el avance guardado de `processing_checkpoint`.
///
/// Una nota no tiene fila en `source` ni nada que procesar: sobre ella, cada
/// operación no hace nada.
class ProcessingStateRepositoryImpl implements ProcessingStateRepository {
  const ProcessingStateRepositoryImpl(this._db);

  final AppDatabase _db;

  $KnowledgeSourcesTable get _sources => _db.knowledgeSources;

  $ProcessingCheckpointsTable get _checkpoints => _db.processingCheckpoints;

  UpdateStatement<$KnowledgeSourcesTable, KnowledgeSourceRow> _update(
    String itemId,
  ) => _db.update(_sources)..where((s) => s.itemId.equals(itemId));

  @override
  Future<int> begin(String itemId) => _db.transaction(() async {
    final row = await (_db.select(
      _sources,
    )..where((s) => s.itemId.equals(itemId))).getSingleOrNull();
    if (row == null) return 0;

    final attempts = row.processingAttempts + 1;
    await _update(itemId).write(
      KnowledgeSourcesCompanion(
        processingStatus: const Value(SourceProcessingStatus.running),
        processingError: const Value(null),
        processingAttempts: Value(attempts),
      ),
    );
    return attempts;
  });

  @override
  Future<void> fail(String itemId, ProcessingFailureReason reason) =>
      _update(itemId).write(
        KnowledgeSourcesCompanion(
          processingStatus: const Value(SourceProcessingStatus.failed),
          processingError: Value(reason.name),
        ),
      );

  @override
  Future<void> succeed(String itemId) => _db.transaction(() async {
    await _update(itemId).write(
      const KnowledgeSourcesCompanion(
        processingError: Value(null),
        processingAttempts: Value(0),
      ),
    );
    await (_db.delete(
      _checkpoints,
    )..where((c) => c.itemId.equals(itemId))).go();
  });

  @override
  Future<Map<int, String>> load(
    String itemId,
    ProcessingCheckpointKind kind,
  ) async {
    final rows = await (_db.select(
      _checkpoints,
    )..where((c) => c.itemId.equals(itemId) & c.kind.equalsValue(kind))).get();
    return {for (final row in rows) row.position: row.content};
  }

  @override
  Future<void> save(
    String itemId,
    ProcessingCheckpointKind kind, {
    required int position,
    required String content,
  }) => _db.transaction(() async {
    await _db
        .into(_checkpoints)
        .insertOnConflictUpdate(
          ProcessingCheckpointsCompanion.insert(
            itemId: itemId,
            kind: kind,
            position: position,
            content: content,
          ),
        );
    // Avanzó: lo interrumpido deja de acercarse al tope de intentos.
    await _update(
      itemId,
    ).write(const KnowledgeSourcesCompanion(processingAttempts: Value(0)));
  });

  @override
  Future<void> requeue(String itemId) => _update(itemId).write(
    const KnowledgeSourcesCompanion(
      processingStatus: Value(SourceProcessingStatus.pending),
      processingError: Value(null),
      processingAttempts: Value(0),
    ),
  );

  @override
  Future<List<String>> recoverInterrupted({
    required int maxAttempts,
    Set<String> inFlight = const {},
  }) => _db.transaction(() async {
    final rows = await _withStatus(SourceProcessingStatus.running).get();

    final resumed = <String>[];
    for (final row in rows) {
      final source = row.readTable(_sources);
      if (inFlight.contains(source.itemId)) continue;

      if (source.processingAttempts >= maxAttempts) {
        await fail(source.itemId, ProcessingFailureReason.interrupted);
        continue;
      }

      // Se vuelve a dejar en espera aunque esté en la papelera: si alguien
      // lo restaura, tiene que volver como "en espera", no como un "en
      // curso" que ya nadie está procesando.
      await _update(source.itemId).write(
        const KnowledgeSourcesCompanion(
          processingStatus: Value(SourceProcessingStatus.pending),
        ),
      );
      if (row.readTable(_db.knowledgeEntries).deletedAt == null) {
        resumed.add(source.itemId);
      }
    }
    return resumed;
  });

  @override
  Future<List<String>> pendingIds() async =>
      _idsOf(await _pendingQuery().get());

  @override
  Stream<List<String>> watchPendingIds() => _pendingQuery().watch().map(_idsOf);

  JoinedSelectStatement<HasResultSet, dynamic> _pendingQuery() =>
      _withStatus(SourceProcessingStatus.pending)
        ..where(_db.knowledgeEntries.deletedAt.isNull());

  List<String> _idsOf(List<TypedResult> rows) => [
    for (final row in rows) row.readTable(_sources).itemId,
  ];

  @override
  Stream<ProcessingFailureReason?> watchFailure(String itemId) =>
      (_db.selectOnly(_sources)
            ..addColumns([_sources.processingStatus, _sources.processingError])
            ..where(_sources.itemId.equals(itemId)))
          .map((row) {
            final status = row.readWithConverter(_sources.processingStatus);
            if (status != SourceProcessingStatus.failed) return null;
            return ProcessingFailureReason.fromStored(
                  row.read(_sources.processingError),
                ) ??
                ProcessingFailureReason.unknown;
          })
          .watchSingleOrNull()
          .distinct();

  @override
  Future<int> requeueFailedWith(ProcessingFailureReason reason) =>
      (_db.update(_sources)..where(
            (s) =>
                s.processingStatus.equalsValue(SourceProcessingStatus.failed) &
                s.processingError.equals(reason.name),
          ))
          .write(
            const KnowledgeSourcesCompanion(
              processingStatus: Value(SourceProcessingStatus.pending),
              processingError: Value(null),
              processingAttempts: Value(0),
            ),
          );

  @override
  Future<bool> isRemoved(String itemId) async =>
      await _inTrashQuery(itemId).getSingleOrNull() ?? true;

  @override
  Stream<bool> watchRemoved(String itemId) => _inTrashQuery(
    itemId,
  ).watchSingleOrNull().map((inTrash) => inTrash ?? true).distinct();

  /// Si [itemId] está en la papelera; sin fila —`null` al leerla— si se
  /// borró para siempre.
  Selectable<bool> _inTrashQuery(String itemId) {
    final entries = _db.knowledgeEntries;
    return (_db.selectOnly(entries)
          ..addColumns([entries.deletedAt])
          ..where(entries.id.equals(itemId)))
        .map((row) => row.read(entries.deletedAt) != null);
  }

  /// Las fuentes con [status] junto a su elemento, en orden de captura: lo
  /// primero que se guardó es lo primero que se procesa.
  JoinedSelectStatement<HasResultSet, dynamic> _withStatus(
    SourceProcessingStatus status,
  ) =>
      _db.select(_sources).join([
          innerJoin(
            _db.knowledgeEntries,
            _db.knowledgeEntries.id.equalsExp(_sources.itemId),
          ),
        ])
        ..where(_sources.processingStatus.equalsValue(status))
        ..orderBy([
          OrderingTerm.asc(_sources.capturedAt),
          OrderingTerm.asc(_db.knowledgeEntries.createdAt),
        ]);
}
