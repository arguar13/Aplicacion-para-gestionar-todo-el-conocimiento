import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/notes/domain/entities/derived_note_mark.dart';
import 'package:sinapsis/features/notes/domain/repositories/derived_note_repository.dart';

class DerivedNoteRepositoryImpl implements DerivedNoteRepository {
  const DerivedNoteRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    Clock clock = DateTime.now,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  KnowledgeEntryWriter get _writer => KnowledgeEntryWriter(_db, clock: _clock);

  @override
  Stream<DerivedNoteMark?> watchMark(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.knowledgeNotes],
      read: () async {
        final row = await (_db.select(
          _db.knowledgeNotes,
        )..where((n) => n.itemId.equals(itemId))).getSingleOrNull();
        final model = row?.generatedByModel;
        final generatedAt = row?.generatedAt;
        if (model == null || generatedAt == null) return null;
        return DerivedNoteMark(
          model: model,
          generatedAt: generatedAt,
          edited: row!.derivedEdited,
        );
      },
      telemetry: _telemetry,
      hint: 'DerivedNoteRepositoryImpl.watchMark',
    );
  }

  @override
  Future<void> markEdited(String itemId) => _writer.markDerivedEdited(itemId);
}
