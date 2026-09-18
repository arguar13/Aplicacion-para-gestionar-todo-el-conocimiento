import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../generated_migrations/schema.dart';

/// La migración de esquema 9→11 —clasificación asistida (F4): la columna
/// `origin` en `ItemPropertyValues` y la tabla `Suggestions`—, probada con
/// `SchemaVerifier`, mismo patrón que `migration_v9_test.dart`.
///
/// Arranca en 9, no en 10: v9→v10 no cambió la forma del esquema (decisión
/// 36), así que no hay snapshot de v10 y `verifier.startAt(9)` representa
/// igual de bien las dos.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('una base nueva (onCreate) trae Suggestions vacía', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.suggestions).get(), isEmpty);
  });

  test('migrar de v9 a v11 agrega la columna origin y la tabla '
      'Suggestions', () async {
    final connection = await verifier.startAt(9);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    // El segundo argumento es la versión REAL de `AppDatabase.
    // schemaVersion` (hoy 13, por F7), no la versión que da nombre a
    // este archivo — `AppDatabase` siempre migra hasta su propio
    // `schemaVersion`.
    await verifier.migrateAndValidate(db, 13);

    expect(await db.select(db.suggestions).get(), isEmpty);
  });

  test('un ItemPropertyValues creado antes de la migración sobrevive con '
      'origin=manual', () async {
    final connection = await verifier.startAt(9);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    final now = DateTime(2026, 9, 19, 10);
    await db
        .into(db.sources)
        .insert(
          SourcesCompanion.insert(
            id: 'src-1',
            kind: SourceKind.webPage,
            capturedAt: now,
          ),
        );
    await db
        .into(db.items)
        .insert(
          ItemsCompanion.insert(
            id: 'item-1',
            title: 'Un elemento',
            sourceId: 'src-1',
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.propertyDefinitions)
        .insert(
          PropertyDefinitionsCompanion.insert(
            id: 'def-1',
            name: 'Región',
            createdAt: now,
          ),
        );
    await db
        .into(db.propertyValues)
        .insert(
          PropertyValuesCompanion.insert(
            id: 'val-1',
            definitionId: 'def-1',
            value: 'Roma',
            createdAt: now,
          ),
        );
    await db
        .into(db.itemPropertyValues)
        .insert(
          ItemPropertyValuesCompanion.insert(
            itemId: 'item-1',
            propertyValueId: 'val-1',
          ),
        );

    // Mismo motivo que el test anterior: versión real, no la del nombre
    // del archivo.
    await verifier.migrateAndValidate(db, 13);

    final assignment = await (db.select(
      db.itemPropertyValues,
    )..where((p) => p.itemId.equals('item-1'))).getSingle();
    expect(assignment.origin, ItemPropertyOrigin.manual);
  });
}
