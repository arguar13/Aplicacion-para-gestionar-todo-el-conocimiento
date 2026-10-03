import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v34.dart' as v34;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 34→35 —lo que dejó pendiente el motor de F27—: lo
/// que cada pasada de la IA completó del tema y la referencia, la huella del
/// texto que vio, y los vectores de las notas y del vocabulario. Aditiva: las
/// pasadas de antes quedan sin huella, y ninguna fila cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v34.DatabaseAtV34 db) async {
    // El esquema v34 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('una-nota', 'Una nota', 'note', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO ai_runs (id, item_id, started_at, finished_at, '
      'relations_created) '
      "VALUES ('pasada', 'una-nota', $seconds, $seconds, 2)",
    );
    await db.customStatement(
      'INSERT INTO property_definitions (id, name, created_at) '
      "VALUES ('tema', 'Tema', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO property_values (id, definition_id, value, created_at) '
      "VALUES ('roma', 'tema', 'Roma', $seconds)",
    );
  }

  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
    ...VaultCounts.viewsAndTemplatesTables,
    ...VaultCounts.notebookTables,
    ...VaultCounts.habitTables,
    ...VaultCounts.quizTables,
    ...VaultCounts.aiTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom34({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(34);
    final oldDb = v34.DatabaseAtV34(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v35', () async {
    await migrateFrom34();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(35));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom34(countsBefore: before);

    expect(await countsOf(db), before);
    expect(before['ai_runs'], 1);
  });

  test('la pasada de antes queda igual, sin huella', () async {
    final db = await migrateFrom34();

    final run = await db.select(db.aiRuns).getSingle();
    expect(run.contentSimhash, isNull);
    expect(run.relationsCreated, 2);
    expect(run.finishedAt, isNotNull);
  });

  test('las tablas nuevas arrancan vacías y aceptan lo suyo', () async {
    final db = await migrateFrom34();
    expect(await db.select(db.aiFieldChanges).get(), isEmpty);
    expect(await db.select(db.noteEmbeddings).get(), isEmpty);
    expect(await db.select(db.propertyValueEmbeddings).get(), isEmpty);

    await db.customStatement('PRAGMA foreign_keys = ON');
    await db
        .into(db.aiFieldChanges)
        .insert(
          AiFieldChangesCompanion.insert(
            id: 'cambio',
            aiRunId: 'pasada',
            field: AiChangedField.space,
            afterValue: 'historia',
          ),
        );
    await db
        .into(db.noteEmbeddings)
        .insert(
          NoteEmbeddingsCompanion.insert(
            itemId: 'una-nota',
            seq: 0,
            vector: Uint8List(4),
            textHash: 'h',
            modelVersion: 'm',
            createdAt: DateTime(2026, 10),
          ),
        );
    await db
        .into(db.propertyValueEmbeddings)
        .insert(
          PropertyValueEmbeddingsCompanion.insert(
            valueId: 'roma',
            label: 'Roma',
            vector: Uint8List(4),
            modelVersion: 'm',
            createdAt: DateTime(2026, 10),
          ),
        );
    await (db.update(db.aiRuns)..where((r) => r.id.equals('pasada'))).write(
      const AiRunsCompanion(contentSimhash: Value('00ff')),
    );

    expect((await db.select(db.aiRuns).getSingle()).contentSimhash, '00ff');

    // Cada cosa se va con lo suyo: la pasada se lleva lo que completó, la
    // nota sus vectores y el valor el suyo.
    await db.customStatement("DELETE FROM item WHERE id = 'una-nota'");
    await db.customStatement("DELETE FROM property_values WHERE id = 'roma'");
    expect(await db.select(db.aiFieldChanges).get(), isEmpty);
    expect(await db.select(db.noteEmbeddings).get(), isEmpty);
    expect(await db.select(db.propertyValueEmbeddings).get(), isEmpty);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom34();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
