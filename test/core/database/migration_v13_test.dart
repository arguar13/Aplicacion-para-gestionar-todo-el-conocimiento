import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';

import '../../generated_migrations/schema.dart';
import '../../support/schema_snapshot.dart';

/// La migración de esquema 11→13 —deduplicación (F7): `dedupHash` en
/// `source` y en `note`, `simhash` nuevo en `note` (en `source` ya
/// existía, reservado desde F1), y la tabla `merged_provenances`—,
/// probada con `SchemaVerifier`, mismo patrón que `migration_v11_test.dart`.
///
/// Arranca en 11, no en 12: v11→v12 no cambió la forma del esquema
/// (solo pobló `chunk`/`fullText`/`contentHash` de catch-up), así que no
/// hay snapshot de v12 y `verifier.startAt(11)` representa igual de bien
/// las dos.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('una base nueva (onCreate) trae merged_provenances vacía', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.mergedProvenances).get(), isEmpty);
  });

  test('migrar de v11 a v13 agrega dedupHash/simhash y la tabla '
      'merged_provenances', () async {
    final connection = await verifier.startAt(11);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    // La forma que se valida es la final (`latestSchemaSnapshot`), no la 13:
    // `AppDatabase` siempre migra hasta su propio `schemaVersion`.
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);

    expect(await db.select(db.mergedProvenances).get(), isEmpty);
  });

  test('una fuente y una nota creadas antes de la migración quedan con '
      'dedupHash/simhash en null', () async {
    final connection = await verifier.startAt(11);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    final now = DateTime(2026, 9, 19, 10);
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: 'entry-source',
            kind: ItemKind.source,
            title: 'Una fuente',
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.knowledgeSources)
        .insert(
          KnowledgeSourcesCompanion.insert(
            itemId: 'entry-source',
            sourceType: SourceKind.webPage,
            capturedAt: now,
            contentHash: 'ya-poblado',
            processingStatus: SourceProcessingStatus.pending,
          ),
        );
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: 'entry-note',
            kind: ItemKind.note,
            title: 'Una nota',
            state: ItemState.captured,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.knowledgeNotes)
        .insert(
          KnowledgeNotesCompanion.insert(
            itemId: 'entry-note',
            noteKind: NoteKind.living,
            maturity: NoteMaturity.seed,
          ),
        );

    await verifier.migrateAndValidate(db, latestSchemaSnapshot);

    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals('entry-source'))).getSingle();
    expect(source.dedupHash, isNull);
    expect(source.simhash, isNull);

    final note = await (db.select(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals('entry-note'))).getSingle();
    expect(note.dedupHash, isNull);
    expect(note.simhash, isNull);
  });
}
