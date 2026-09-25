import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 27→28 —la racha (F17, D6)—: una tabla nueva y
/// vacía, `habit_event`.
///
/// No referencia ningún elemento ni ninguna otra fila: solo dice que una de
/// las dos acciones sin rastro propio —triar la Bandeja, resolver algo en
/// Vocabulario— pasó, y cuándo. Se siembra la base de v22 (mismo motivo que
/// `migration_v27_test.dart`) y se migra de un tirón hasta la versión
/// actual.
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

  test('la migración llega a la forma del snapshot de v28', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(28));
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
  });

  test('habit_event nace vacía', () async {
    final db = await migrateFrom22();

    expect(await db.select(db.habitEvents).get(), isEmpty);
  });

  test('se puede guardar un evento después de migrar', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.habitEvents)
        .insert(
          HabitEventsCompanion.insert(
            id: 'ev-1',
            kind: HabitEventKind.triage,
            occurredAt: now,
          ),
        );

    final event = await db.select(db.habitEvents).getSingle();
    expect(event.kind, HabitEventKind.triage);
    expect(event.occurredAt, now);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
