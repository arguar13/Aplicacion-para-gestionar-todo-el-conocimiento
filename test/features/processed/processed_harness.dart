import 'package:drift/drift.dart' show QueryExecutor, Variable;
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';

import '../../support/fake_id_generator.dart';
import '../../support/test_vault.dart';

class _SilentTelemetry extends Mock implements TelemetryService {}

/// Una bóveda de prueba con su repositorio de procesados y el caso de uso
/// (F41), sobre SQLite real.
class ProcessedHarness {
  ProcessedHarness._(this.vault, {ProcessedWorker? worker})
    : repository = ProcessedRepositoryImpl(
        database: vault.db,
        telemetry: _SilentTelemetry(),
        ids: FakeIdGenerator(prefix: 'parte-${vault.deviceId}'),
        clock: () => vault.now,
      ) {
    process = ProcessSourceUseCase(
      repository,
      worker: worker ?? runProcessedWork,
    );
  }

  /// Con [worker], lo pesado pasa por ahí en vez de por [runProcessedWork]; con
  /// [executor], la base es esa —una en su propio hilo, como en la app—.
  static Future<ProcessedHarness> create({
    String deviceId = 'tel',
    ProcessedWorker? worker,
    QueryExecutor? executor,
  }) async => ProcessedHarness._(
    await TestVault.create(deviceId: deviceId, executor: executor),
    worker: worker,
  );

  final TestVault vault;
  final ProcessedRepositoryImpl repository;
  late final ProcessSourceUseCase process;

  AppDatabase get db => vault.db;

  Future<void> close() => vault.db.close();

  /// Una oración de [kind] sobre el texto de [itemId] (la forma de
  /// `saveSource`): de [start] a [end] de [text], copiada como la copia F36.
  Future<void> addSentence(
    String id,
    String itemId,
    String text, {
    required int start,
    required int end,
    StudyMarkKind kind = StudyMarkKind.summary,
  }) => db
      .into(db.studyMarks)
      .insert(
        StudyMarksCompanion.insert(
          id: id,
          renditionId: 'rend-$itemId',
          kind: kind,
          origin: ContentOrigin.ai,
          startOffset: start,
          endOffset: end,
          excerpt: text.substring(start, end),
          createdAt: vault.now,
        ),
      );

  /// Lo que la base guarda de la fuente [itemId] y de lo que cuelga de
  /// ella, fila por fila y columna por columna: lo que procesar nunca puede
  /// cambiar.
  Future<List<String>> sourceSnapshot(String itemId) async {
    Future<List<String>> rows(String sql) async => [
      for (final row
          in await db
              .customSelect(sql, variables: [Variable.withString(itemId)])
              .get())
        row.data.toString(),
    ];
    return [
      ...await rows('SELECT * FROM item WHERE id = ?'),
      ...await rows('SELECT * FROM source WHERE item_id = ?'),
      ...await rows('SELECT * FROM renditions WHERE item_id = ? ORDER BY id'),
      ...await rows(
        'SELECT m.* FROM study_marks m JOIN renditions r '
        'ON r.id = m.rendition_id WHERE r.item_id = ? ORDER BY m.id',
      ),
      ...await rows(
        'SELECT * FROM field_version WHERE item_id = ? ORDER BY field_name',
      ),
      ...await rows('SELECT * FROM chunks WHERE item_id = ? ORDER BY seq'),
      ...await rows('SELECT * FROM item_spaces WHERE item_id = ?'),
      ...await rows(
        'SELECT * FROM item_property_values WHERE item_id = ? '
        'ORDER BY property_value_id',
      ),
    ];
  }
}
