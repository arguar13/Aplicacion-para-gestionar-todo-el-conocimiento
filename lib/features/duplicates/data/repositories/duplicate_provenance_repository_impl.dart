import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/domain/entities/merged_provenance.dart';
import 'package:sinapsis/features/duplicates/domain/repositories/duplicate_provenance_repository.dart';

class DuplicateProvenanceRepositoryImpl
    implements DuplicateProvenanceRepository {
  const DuplicateProvenanceRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
  }) : _db = database,
       _telemetry = telemetry;

  final AppDatabase _db;
  final TelemetryService _telemetry;

  @override
  Stream<List<MergedProvenance>> watchMergedProvenancesForItem(String itemId) {
    return watchQuery(
      db: _db,
      tables: [_db.mergedProvenances],
      read: () async {
        final rows =
            await (_db.select(_db.mergedProvenances)
                  ..where((p) => p.itemId.equals(itemId))
                  ..orderBy([(p) => OrderingTerm(expression: p.mergedAt)]))
                .get();
        return rows.map(_toMergedProvenance).toList();
      },
      telemetry: _telemetry,
      hint: 'DuplicateProvenanceRepositoryImpl.watchMergedProvenancesForItem',
    );
  }

  MergedProvenance _toMergedProvenance(MergedProvenanceRow row) {
    return MergedProvenance(
      id: row.id,
      itemId: row.itemId,
      sourceKind: row.sourceKind,
      capturedAt: row.capturedAt,
      mergedAt: row.mergedAt,
      url: row.url,
      authorName: row.authorName,
      authorUrl: row.authorUrl,
      publishedAt: row.publishedAt,
    );
  }
}
