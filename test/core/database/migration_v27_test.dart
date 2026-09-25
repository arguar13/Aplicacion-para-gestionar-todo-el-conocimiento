import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 26→27 —la exportación incremental a Anki (F17,
/// D4)—: una columna nueva y nula en `flashcards`.
///
/// Es aditiva: ninguna tarjeta existente cambia de sentido —una tarjeta de
/// antes de esto ya «nunca se exportó», que es justo lo que
/// `last_exported_at` nulo sigue significando—. Se siembra la base de v22
/// (mismo motivo que `migration_v26_test.dart`: v23 en adelante ya no
/// traen Companion utilizable para sembrar a mano) y se migra de un tirón
/// hasta la versión actual.
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
    await db
        .into(db.flashcards)
        .insert(
          v22.FlashcardsCompanion.insert(
            id: 'tarjeta',
            itemId: 'nota',
            front: 'pregunta',
            back: 'respuesta',
            dueAt: seconds,
            createdAt: seconds,
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

  test('la migración llega a la forma del snapshot de v27', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(27));
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
    expect(before['flashcards'], 1);
  });

  test('una tarjeta de antes de la migración queda sin exportar', () async {
    final db = await migrateFrom22();

    final card = await (db.select(
      db.flashcards,
    )..where((f) => f.id.equals('tarjeta'))).getSingle();

    expect(card.lastExportedAt, isNull);
  });

  test('una exportación nueva puede marcar cuándo se exportó', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await (db.update(db.flashcards)..where((f) => f.id.equals('tarjeta')))
        .write(FlashcardsCompanion(lastExportedAt: Value(now)));

    final card = await (db.select(
      db.flashcards,
    )..where((f) => f.id.equals('tarjeta'))).getSingle();
    expect(card.lastExportedAt, now);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
