import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 30→31 —el avance guardado de los trabajos largos
/// (F21)—: una tabla nueva, `processing_checkpoint`, vacía. Aditiva: ninguna
/// fila de antes cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v22.DatabaseAtV22 db) async {
    await db
        .into(db.item)
        .insert(
          v22.ItemCompanion.insert(
            id: 'libro',
            title: 'Un libro escaneado',
            kind: 'source',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'dispositivo-a',
          ),
        );
    await db
        .into(db.source)
        .insert(
          v22.SourceCompanion.insert(
            itemId: 'libro',
            sourceType: 'document',
            capturedAt: seconds,
            contentHash: 'hash',
            processingStatus: 'done',
          ),
        );
  }

  /// Las tablas que ya existían en v22.
  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom22({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v31', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(31));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom22(countsBefore: before);

    expect(await countsOf(db), before);
    // Y no es una comparación de ceros.
    expect(before['item'], 1);
  });

  test('la tabla nueva empieza vacía, y guarda avance después', () async {
    final db = await migrateFrom22();
    expect(await db.select(db.processingCheckpoints).get(), isEmpty);

    await db
        .into(db.processingCheckpoints)
        .insert(
          ProcessingCheckpointsCompanion.insert(
            itemId: 'libro',
            kind: ProcessingCheckpointKind.ocrPage,
            position: 0,
            content: 'Página uno',
          ),
        );

    expect(await db.select(db.processingCheckpoints).get(), hasLength(1));
  });

  test('el avance se va solo con el elemento', () async {
    final db = await migrateFrom22();
    await db
        .into(db.processingCheckpoints)
        .insert(
          ProcessingCheckpointsCompanion.insert(
            itemId: 'libro',
            kind: ProcessingCheckpointKind.ocrPage,
            position: 0,
            content: 'Página uno',
          ),
        );

    await db.customStatement("DELETE FROM item WHERE id = 'libro'");

    expect(await db.select(db.processingCheckpoints).get(), isEmpty);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
