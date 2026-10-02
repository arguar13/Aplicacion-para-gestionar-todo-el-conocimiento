import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v32.dart' as v32;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 32→33 —cuándo se dice cada palabra de una
/// transcripción (F23)—: una columna nueva en `renditions`, nula en todo lo
/// de antes ("no se midió"). Aditiva: ninguna fila cambia, y el texto de
/// cada transcripción queda tal cual.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v32.DatabaseAtV32 db) async {
    // El esquema v32 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('nota-de-voz', 'Nota de voz', 'source', "
      "'processed', $seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO source (item_id, source_type, captured_at, content_hash, '
      "processing_status) VALUES ('nota-de-voz', 'audio', $seconds, 'hash', "
      "'done')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'nota-de-voz', 'plainText', "
      "'[0:00] No hay intervención docente ahí.', 1, $seconds)",
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom32({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(32);
    final oldDb = v32.DatabaseAtV32(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v33', () async {
    await migrateFrom32();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(33));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom32(countsBefore: before);

    expect(await countsOf(db), before);
    expect(before['renditions'], 1);
  });

  test('una transcripción de antes queda sin tiempos y con su texto intacto, '
      'y los tiempos se pueden guardar después', () async {
    final db = await migrateFrom32();

    final row = await db.select(db.renditions).getSingle();
    expect(row.wordTimings, isNull);
    expect(row.content, '[0:00] No hay intervención docente ahí.');

    await (db.update(db.renditions)..where((r) => r.id.equals('texto'))).write(
      const RenditionsCompanion(wordTimings: Value('{"w":["No"],"ms":[0]}')),
    );
    expect(
      (await db.select(db.renditions).getSingle()).wordTimings,
      '{"w":["No"],"ms":[0]}',
    );
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom32();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
