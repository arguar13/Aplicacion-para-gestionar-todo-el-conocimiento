import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/reference/domain/repositories/reference_repository.dart';

/// [ReferenceRepository] sobre la base: lee con `ReferenceReader` y escribe
/// con el escritor único.
class ReferenceRepositoryImpl implements ReferenceRepository {
  ReferenceRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock,
       _reader = ReferenceReader(database);

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;
  final ReferenceReader _reader;

  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  @override
  Stream<ReferenceData> watch(String itemId) => watchQuery(
    db: _db,
    // Renombrar a un autor en el vocabulario cambia lo que la referencia
    // muestra: el lector sabe de qué tablas depende.
    tables: _reader.tables,
    read: () => read(itemId),
    telemetry: _telemetry,
    hint: 'ReferenceRepositoryImpl.watch',
  );

  @override
  Future<ReferenceData> read(String itemId) => _reader.read(itemId);

  @override
  Future<bool> saveReference(String itemId, ReferenceData reference) =>
      _writer.setReference(itemId, reference);

  @override
  Future<bool> savePublishedAt(String itemId, DateTime? publishedAt) =>
      _writer.setFieldFromText(
        itemId,
        EntryField.publishedAt,
        publishedAt == null
            ? null
            : '${publishedAt.millisecondsSinceEpoch ~/ 1000}',
      );
}
