import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 23→24 —cuadernos (F16)—: un subconjunto con
/// nombre de la bóveda, manual o por consulta guardada (D1).
///
/// Es aditiva: dos tablas nuevas, ninguna columna tocada. Se siembra la base
/// de v22 (con `schemaAt(22)` y las clases generadas de esa versión —v23 ya
/// no trae Companion utilizable para sembrar a mano, mismo motivo que
/// `migration_v23_test.dart`—) y se migra de un tirón hasta la versión
/// actual, pasando por v23. Lo que se comprueba es que no cambia ninguna
/// fila de lo que ya existía en v22 y que las tablas nuevas —de v23 y de
/// v24— nacen vacías, con las columnas que dicen.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  /// Una bóveda como la deja v22: un elemento y una categoría de vocabulario.
  Future<void> seedVault(v22.DatabaseAtV22 db) async {
    await db
        .into(db.item)
        .insert(
          v22.ItemCompanion.insert(
            id: 'art',
            title: 'Un artículo',
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
            itemId: 'art',
            sourceType: 'webPage',
            capturedAt: seconds,
            contentHash: '',
            processingStatus: 'done',
          ),
        );
    await db
        .into(db.propertyDefinitions)
        .insert(
          v22.PropertyDefinitionsCompanion.insert(
            id: 'def-tema',
            name: 'Tema',
            createdAt: seconds,
            isSystem: const Value(1),
          ),
        );
  }

  /// Las tablas que la migración no debe cambiar de tamaño. Se siembra desde
  /// v22 —ver el porqué en el comentario de arriba—, así que solo entran acá
  /// las que ya existían en esa versión: vistas guardadas y plantillas
  /// (v23) nacen vacías en este mismo recorrido, no hay fila sembrada que
  /// perder. Su propia compuerta vive en la migración real
  /// (`_requireSameCounts(step: 'v24')` en `app_database.dart`), que sí las
  /// cuenta porque corre DESPUÉS de que el paso v23 las crea, dentro de la
  /// misma transacción.
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

  test('la migración llega a la forma del snapshot de v24', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(24));
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
    expect(before['property_definitions'], 1);
  });

  test('las tablas nuevas existen y empiezan vacías', () async {
    final db = await migrateFrom22();

    for (final table in ['notebook', 'notebook_item']) {
      final n = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      expect(n.read<int>('n'), 0, reason: table);
    }
  });

  test('un cuaderno manual y uno por consulta se pueden escribir', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: 'nb-manual',
            name: 'A mano',
            mode: NotebookMode.manual,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: 'nb-query',
            name: 'Por consulta',
            mode: NotebookMode.query,
            queryJson: const Value('{}'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.notebookItems)
        .insert(
          NotebookItemsCompanion.insert(notebookId: 'nb-manual', itemId: 'art'),
        );

    final notebooks = await db.select(db.notebooks).get();
    final items = await db.select(db.notebookItems).get();
    expect(notebooks, hasLength(2));
    expect(items, hasLength(1));
    expect(items.single.itemId, 'art');
  });

  test('borrar el elemento saca la fila de sus cuadernos (cascada)', () async {
    final db = await migrateFrom22();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.notebooks)
        .insert(
          NotebooksCompanion.insert(
            id: 'nb-manual',
            name: 'A mano',
            mode: NotebookMode.manual,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.notebookItems)
        .insert(
          NotebookItemsCompanion.insert(notebookId: 'nb-manual', itemId: 'art'),
        );

    await (db.delete(
      db.knowledgeEntries,
    )..where((i) => i.id.equals('art'))).go();

    expect(await db.select(db.notebookItems).get(), isEmpty);
    // El cuaderno en sí sigue existiendo: sacar un elemento no lo borra.
    expect(await db.select(db.notebooks).get(), hasLength(1));
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
