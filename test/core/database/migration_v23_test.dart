import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v22.dart' as v22;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 22→23 —cuadernos y vistas (F16)—: vistas guardadas
/// de la Biblioteca y plantillas de nota.
///
/// Es aditiva: dos tablas nuevas, ninguna columna tocada. Se siembra la base
/// de v22 (con `schemaAt(22)` y las clases generadas de esa versión) y recién
/// después se abre `AppDatabase` encima. Lo que se comprueba es que no cambia
/// ninguna fila de lo que había y que las tablas nuevas nacen vacías, con las
/// columnas que dicen.
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

  /// Las tablas que la migración no debe cambiar de tamaño.
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

  test('la migración llega a la forma del snapshot de v23', () async {
    await migrateFrom22();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(23));
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

    for (final table in ['saved_view', 'note_template']) {
      final n = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      expect(n.read<int>('n'), 0, reason: table);
    }
  });

  test('una vista guardada y una plantilla se pueden escribir', () async {
    final db = await migrateFrom22();

    await db
        .into(db.savedViews)
        .insert(
          SavedViewsCompanion.insert(
            id: 'vw-1',
            name: 'Sin leer, más nuevo primero',
            queryJson: '{}',
            viewMode: LibraryViewMode.list,
            position: 0,
            createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          ),
        );
    await db
        .into(db.noteTemplates)
        .insert(
          NoteTemplatesCompanion.insert(
            id: 'tpl-1',
            name: 'Reunión',
            blocksJson: '[]',
            propertiesJson: '{}',
            createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          ),
        );

    final views = await db.select(db.savedViews).get();
    final templates = await db.select(db.noteTemplates).get();
    expect(views, hasLength(1));
    expect(views.single.pinned, isFalse);
    expect(templates, hasLength(1));
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom22();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
