import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/ai_changed_field.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v36.dart' as v36;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 36→37: qué le pidieron a cada pasada de la IA
/// (`ai_runs.scope`). Hasta v36 una pasada de solo tarjetas (F30) se marcaba
/// con una fila de `ai_field_changes` con el campo `flashcardsOnly`; la
/// migración la pasa a la columna y borra la marca. Nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v36.DatabaseAtV36 db) async {
    // El esquema v36 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('roma', 'Roma', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    for (final run in ['organizo', 'tarjetas']) {
      await db.customStatement(
        'INSERT INTO ai_runs (id, item_id, started_at, finished_at) '
        "VALUES ('$run', 'roma', $seconds, $seconds)",
      );
    }
    // Un dato que completó la pasada de organizar: se queda.
    await db.customStatement(
      'INSERT INTO ai_field_changes (id, ai_run_id, field, after_value) '
      "VALUES ('tema', 'organizo', '${AiChangedField.space.name}', 'historia')",
    );
    // La marca de la pasada de solo tarjetas, como la escribía v36: se va.
    await db.customStatement(
      'INSERT INTO ai_field_changes (id, ai_run_id, field, after_value) '
      "VALUES ('marca', 'tarjetas', '$kLegacyFlashcardsOnlyField', "
      "'flashcards')",
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

  Future<AppDatabase> migrateFrom36({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(36);
    final oldDb = v36.DatabaseAtV36(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v37', () async {
    await migrateFrom36();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(37));
  });

  test('la marca de solo tarjetas pasa a la columna y se borra', () async {
    final db = await migrateFrom36();

    final scopes = {
      for (final run in await db.select(db.aiRuns).get()) run.id: run.scope,
    };
    expect(scopes, {
      'organizo': AiRunScope.organize,
      'tarjetas': AiRunScope.flashcards,
    });

    final changes = await db.select(db.aiFieldChanges).get();
    expect(changes.map((c) => c.id), ['tema']);
    expect(changes.single.field, AiChangedField.space);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom36(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
