import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/migrate_tags_to_property_values_v9.dart';
import 'package:sinapsis/core/database/migrations/seed_system_property_categories_v9.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/id_generator.dart';

import '../../generated_migrations/schema.dart';
import '../../support/silent_logger.dart';

/// La migración de esquema 8→9 —vocabulario controlado tipado: columnas
/// nuevas en `PropertyDefinitions`/`PropertyValues`, la tabla
/// `PropertyAliases`, la siembra de "Tema"/"Fecha del hecho", y la
/// migración de etiquetas existentes a `PropertyValue` bajo "Tema"—,
/// probada con `SchemaVerifier`, mismo patrón que `migration_v8_test.dart`.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  Future<void> expectSystemCategories(AppDatabase db) async {
    final tema = await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals('Tema'))).getSingle();
    final fecha = await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals('Fecha del hecho'))).getSingle();

    expect(tema.isSystem, isTrue);
    expect(tema.type, PropertyValueType.text);
    expect(fecha.isSystem, isTrue);
    expect(fecha.type, PropertyValueType.date);
  }

  test('una base nueva (onCreate) trae PropertyAliases vacía y las '
      'categorías de sistema ya sembradas', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.propertyAliases).get(), isEmpty);
    await expectSystemCategories(db);
  });

  test('migrar de v8 a v9 agrega las columnas, la tabla, y siembra las '
      'categorías de sistema', () async {
    final connection = await verifier.startAt(8);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 9);

    expect(await db.select(db.propertyAliases).get(), isEmpty);
    await expectSystemCategories(db);
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

  group('seedSystemPropertyCategories', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('correrla dos veces no duplica las categorías', () async {
      await seedSystemPropertyCategories(db, ids: const UuidV7Generator());
      await seedSystemPropertyCategories(db, ids: const UuidV7Generator());

      final definitions = await db.select(db.propertyDefinitions).get();
      expect(definitions.where((d) => d.name == 'Tema'), hasLength(1));
      expect(
        definitions.where((d) => d.name == 'Fecha del hecho'),
        hasLength(1),
      );
    });

    test('si "Tema" existe pero no está marcada de sistema, se promueve en '
        'vez de duplicarla', () async {
      // `db` ya sembró "Tema" (isSystem=true) en su propio `onCreate`.
      // Encadenar `SchemaVerifier` con una segunda siembra manual sobre
      // el esquema histórico —para simular "ya existía a mano antes de
      // esta versión"— reproduce el mismo problema de instancias de
      // `GeneratedDatabase` compitiendo por una conexión que ya
      // documentó F1: se degrada la fila real a mano en su lugar,
      // ejercitando la misma rama de "reusar y promover" de
      // `_ensureSystemCategory` sin ese riesgo.
      final original = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Tema'))).getSingle();
      await (db.update(db.propertyDefinitions)
            ..where((d) => d.id.equals(original.id)))
          .write(const PropertyDefinitionsCompanion(isSystem: Value(false)));

      await seedSystemPropertyCategories(db, ids: const UuidV7Generator());

      final temas = await (db.select(
        db.propertyDefinitions,
      )..where((d) => d.name.equals('Tema'))).get();

      expect(temas, hasLength(1));
      expect(temas.single.id, original.id);
      expect(temas.single.isSystem, isTrue);
    });
  });

  group('migrateTagsToPropertyValues', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<String> seedItem() async {
      final now = DateTime(2026, 9, 17);
      final n = DateTime.now().microsecondsSinceEpoch;
      await db
          .into(db.sources)
          .insert(
            SourcesCompanion.insert(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
            ),
          );
      await db
          .into(db.items)
          .insert(
            ItemsCompanion.insert(
              id: 'item-$n',
              title: 'Un elemento',
              sourceId: 'src-$n',
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return 'item-$n';
    }

    Future<String> temaId() async => (await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals('Tema'))).getSingle()).id;

    test(
      'cada etiqueta migra a un valor bajo Tema, sin tocar Tags/ItemTags',
      () async {
        final now = DateTime(2026, 9, 17);
        final itemId = await seedItem();
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: 'tag-1',
                name: 'Filosofía',
                createdAt: now,
              ),
            );
        await db
            .into(db.itemTags)
            .insert(ItemTagsCompanion.insert(itemId: itemId, tagId: 'tag-1'));

        await migrateTagsToPropertyValues(
          db,
          ids: const UuidV7Generator(),
          logger: const SilentLogger(),
        );

        final tema = await temaId();
        final value = await (db.select(
          db.propertyValues,
        )..where((v) => v.definitionId.equals(tema))).getSingle();
        final assignment =
            await (db.select(db.itemPropertyValues)..where(
                  (a) =>
                      a.itemId.equals(itemId) &
                      a.propertyValueId.equals(value.id),
                ))
                .getSingleOrNull();

        expect(value.value, 'Filosofía');
        expect(value.id, isNot('tag-1'), reason: 'id nuevo, no el del Tag');
        expect(assignment, isNotNull);
        expect(await db.select(db.tags).get(), hasLength(1));
        expect(await db.select(db.itemTags).get(), hasLength(1));
      },
    );

    test('una etiqueta cuyo nombre ya existe como valor bajo Tema reusa esa '
        'fila', () async {
      final now = DateTime(2026, 9, 17);
      final itemId = await seedItem();
      final tema = await temaId();
      await db
          .into(db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'val-preexistente',
              definitionId: tema,
              value: 'Filosofía',
              createdAt: now,
            ),
          );
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(
              id: 'tag-1',
              name: 'filosofía',
              createdAt: now,
            ),
          );
      await db
          .into(db.itemTags)
          .insert(ItemTagsCompanion.insert(itemId: itemId, tagId: 'tag-1'));

      await migrateTagsToPropertyValues(
        db,
        ids: const UuidV7Generator(),
        logger: const SilentLogger(),
      );

      final values = await (db.select(
        db.propertyValues,
      )..where((v) => v.definitionId.equals(tema))).get();
      expect(values, hasLength(1));
      expect(values.single.id, 'val-preexistente');
    });

    test(
      'una etiqueta con nombre vacío se reporta y no rompe el resto',
      () async {
        final now = DateTime(2026, 9, 17);
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(id: 'tag-1', name: ' ', createdAt: now),
            );
        await db
            .into(db.tags)
            .insert(
              TagsCompanion.insert(
                id: 'tag-2',
                name: 'Historia',
                createdAt: now,
              ),
            );

        await migrateTagsToPropertyValues(
          db,
          ids: const UuidV7Generator(),
          logger: const SilentLogger(),
        );

        final tema = await temaId();
        final values = await (db.select(
          db.propertyValues,
        )..where((v) => v.definitionId.equals(tema))).get();
        final issues = await db.select(db.migrationIssues).get();

        expect(values.map((v) => v.value), ['Historia']);
        expect(issues, hasLength(1));
        expect(issues.single.stage, 'migrate_tags');
        expect(issues.single.itemId, 'tag-1');
      },
    );
  });
}
