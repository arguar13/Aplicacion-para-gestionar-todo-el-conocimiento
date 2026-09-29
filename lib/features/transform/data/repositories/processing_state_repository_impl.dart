import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/processing_failure_reason.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/features/transform/domain/repositories/processing_state_repository.dart';

/// [ProcessingStateRepository] sobre las columnas de procesamiento de
/// `source`: `processing_status`, `processing_error` y `processing_attempts`.
///
/// Una nota no tiene fila en `source` ni nada que procesar: sobre ella, cada
/// operación no hace nada.
class ProcessingStateRepositoryImpl implements ProcessingStateRepository {
  const ProcessingStateRepositoryImpl(this._db);

  final AppDatabase _db;

  $KnowledgeSourcesTable get _sources => _db.knowledgeSources;

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
  Future<void> succeed(String itemId) => _update(itemId).write(
    const KnowledgeSourcesCompanion(
      processingError: Value(null),
      processingAttempts: Value(0),
    ),
  );

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
  Future<List<String>> pendingIds() async {
    final query = _withStatus(SourceProcessingStatus.pending)
      ..where(_db.knowledgeEntries.deletedAt.isNull());
    final rows = await query.get();
    return [for (final row in rows) row.readTable(_sources).itemId];
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
