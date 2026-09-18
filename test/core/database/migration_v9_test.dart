import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';

import '../../generated_migrations/schema.dart';

/// La migración de esquema 8→9 —vocabulario controlado tipado: columnas
/// nuevas en `PropertyDefinitions`/`PropertyValues` y la tabla
/// `PropertyAliases`—, probada con `SchemaVerifier`, mismo patrón que
/// `migration_v8_test.dart`.
///
/// Sin siembra de categorías de sistema todavía —eso es un paso
/// posterior—: acá solo se verifica que el esquema migra bien y que las
/// categorías/valores existentes sobreviven con los valores por defecto.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('una base nueva (onCreate) trae las columnas nuevas y PropertyAliases '
      'vacía', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.propertyAliases).get(), isEmpty);
  });

  test('migrar de v8 a v9 agrega las columnas y la tabla, vacías', () async {
    final connection = await verifier.startAt(8);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 9);

    expect(await db.select(db.propertyAliases).get(), isEmpty);
  });

  test('una categoría/valor creados antes de la migración sobreviven con '
      'type=text e isSystem=false', () async {
    final connection = await verifier.startAt(8);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    final now = DateTime(2026, 9, 17, 10);
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

    await verifier.migrateAndValidate(db, 9);

    final definition = await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.id.equals('def-1'))).getSingle();
    final value = await (db.select(
      db.propertyValues,
    )..where((v) => v.id.equals('val-1'))).getSingle();

    expect(definition.type, PropertyValueType.text);
    expect(definition.isSystem, isFalse);
    expect(value.value, 'Roma');
    expect(value.numberValue, isNull);
    expect(value.dateFromYear, isNull);
  });

  group('esquema nuevo', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('un alias es único dentro de la categoría, no globalmente', () async {
      final now = DateTime(2026, 9, 17);
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-region',
              name: 'Región',
              createdAt: now,
            ),
          );
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-ciudad-natal',
              name: 'Ciudad natal',
              createdAt: now,
            ),
          );
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'val-bizancio',
              definitionId: 'def-region',
              value: 'Bizancio',
              createdAt: now,
            ),
          );
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'val-otra',
              definitionId: 'def-ciudad-natal',
              value: 'Otra ciudad',
              createdAt: now,
            ),
          );

      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-1',
              propertyValueId: 'val-bizancio',
              definitionId: 'def-region',
              alias: 'Roma',
              createdAt: now,
            ),
          );

      // Mismo alias "Roma", pero bajo otra categoría: no es una colisión.
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-2',
              propertyValueId: 'val-otra',
              definitionId: 'def-ciudad-natal',
              alias: 'Roma',
              createdAt: now,
            ),
          );

      expect(await db.select(db.propertyAliases).get(), hasLength(2));

      // El mismo alias, misma categoría: sí es una colisión.
      expect(
        () => db
            .into(db.propertyAliases)
            .insert(
              PropertyAliasesCompanion.insert(
                id: 'alias-3',
                propertyValueId: 'val-bizancio',
                definitionId: 'def-region',
                alias: 'roma',
                createdAt: now,
              ),
            ),
        throwsA(isA<Object>()),
      );
    });

    test('borrar un PropertyValue borra sus alias en cascada', () async {
      final now = DateTime(2026, 9, 17);
      await db
          .into(db.propertyDefinitions)
          .insert(
            PropertyDefinitionsCompanion.insert(
              id: 'def-region',
              name: 'Región',
              createdAt: now,
            ),
          );
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'val-bizancio',
              definitionId: 'def-region',
              value: 'Bizancio',
              createdAt: now,
            ),
          );
      await db
          .into(db.propertyAliases)
          .insert(
            PropertyAliasesCompanion.insert(
              id: 'alias-1',
              propertyValueId: 'val-bizancio',
              definitionId: 'def-region',
              alias: 'Constantinopla',
              createdAt: now,
            ),
          );

      await (db.delete(
        db.propertyValues,
      )..where((v) => v.id.equals('val-bizancio'))).go();

      expect(await db.select(db.propertyAliases).get(), isEmpty);
    });
  });
}
