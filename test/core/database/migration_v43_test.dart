import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v42.dart' as v42;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 42→43: lo que costó cada pasada de la IA (F39,
/// paso 6). Tres columnas en `ai_runs` —el tiempo que el modelo trabajó y los
/// tokens que leyó y escribió— que en todo lo de antes dicen 0. Nada más
/// cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v42.DatabaseAtV42 db) async {
    // El esquema v42 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('libro', 'Un libro', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO ai_runs (id, item_id, model, started_at, finished_at, '
      'relations_created, scope) VALUES '
      "('pasada', 'libro', 'gemma4E4b', $seconds, ${seconds + 60}, 2, "
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
    ...VaultCounts.aiFieldChangeTables,
    ...VaultCounts.contentTrashTables,
    ...VaultCounts.studyTables,
    ...VaultCounts.itemSpaceTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom42({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(42);
    final oldDb = v42.DatabaseAtV42(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v43', () async {
    await migrateFrom42();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(43));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(43));
  });

  test('una pasada de antes queda con 0 de tiempo y de tokens, y con todo '
      'lo suyo', () async {
    final db = await migrateFrom42();

    final run = await db.select(db.aiRuns).getSingle();
    expect(run.workMillis, 0);
    expect((run.inputTokens, run.outputTokens), (0, 0));
    expect(run.model, 'gemma4E4b');
    expect(run.relationsCreated, 2);
    expect(run.scope, AiRunScope.flashcards);
    expect(run.finishedAt, isNotNull);
  });

  test('una pasada nueva guarda su costo, y el alcance de estudio', () async {
    final db = await migrateFrom42();

    await db
        .into(db.aiRuns)
        .insert(
          AiRunsCompanion.insert(
            id: 'estudio',
            itemId: 'libro',
            startedAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            scope: const Value(AiRunScope.study),
            workMillis: const Value(125000),
            inputTokens: const Value(9000),
            outputTokens: const Value(1500),
          ),
        );

    final row = await (db.select(
      db.aiRuns,
    )..where((r) => r.id.equals('estudio'))).getSingle();
    expect(row.scope, AiRunScope.study);
    expect(row.workMillis, 125000);
    expect((row.inputTokens, row.outputTokens), (9000, 1500));
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom42(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
