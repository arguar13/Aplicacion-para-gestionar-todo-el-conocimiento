import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 25→26 —la marca de generado por IA (F16, D3)—:
/// tres columnas nuevas en `note`, `derived_edited` en falso en vez de
/// nula.
///
/// Es aditiva: ninguna fila existente cambia de sentido —una nota de antes
/// de esto ya era «no generada», que es justo lo que `generated_by_model`
/// nulo sigue significando—. Se siembra la base de v22 (con `schemaAt(22)`
/// y las clases generadas de esa versión —v23 en adelante ya no traen
/// Companion utilizable para sembrar a mano, mismo motivo que
/// `migration_v23_test.dart`—) y se migra de un tirón hasta la versión
/// actual, pasando por v23, v24 y v25.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v22.DatabaseAtV22 db) async {
    await db
        .into(db.item)
        .insert(
          v22.ItemCompanion.insert(
            id: 'nota',
            title: 'Una nota de antes',
            kind: 'note',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'dispositivo-a',
          ),
        );
    await db
        .into(db.note)
        .insert(
          v22.NoteCompanion.insert(
            itemId: 'nota',
            noteKind: 'living',
            maturity: 'seed',
          ),
        );
  }

  /// Las tablas que la migración no debe cambiar de tamaño: todo lo que ya
  /// existía en v22.
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

  Future<AppDatabase> migrateFrom22() async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await seedVault(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v26', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(26));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final schema = await verifier.schemaAt(22);
    final oldDb = v22.DatabaseAtV22(schema.newConnection());
    await seedVault(oldDb);
    final before = await countsOf(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    final after = await countsOf(db);

    expect(after, before);
    // Y no es una comparación de ceros.
    expect(before['item'], 1);
    expect(before['note'], 1);
  });

  test('una nota de antes de la migración queda sin marca, `derived_edited` '
      'en falso', () async {
    final db = await migrateFrom22();

    final note = await (db.select(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals('nota'))).getSingle();

    expect(note.generatedByModel, isNull);
    expect(note.generatedAt, isNull);
    expect(note.derivedEdited, isFalse);
  });

  test('un derivado nuevo puede llevar su marca', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals('nota'))).write(
      KnowledgeNotesCompanion(
        generatedByModel: const Value('gemma-3n'),
        generatedAt: Value(now),
      ),
    );

    final note = await (db.select(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals('nota'))).getSingle();
    expect(note.generatedByModel, 'gemma-3n');
    expect(note.generatedAt, now);
    expect(note.derivedEdited, isFalse);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
