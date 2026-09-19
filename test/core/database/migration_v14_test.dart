import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v13.dart' as v13;

/// La migración de datos 13→14 —etiquetas unificadas con propiedades (F8)—.
///
/// No cambia la forma del esquema, así que no hay snapshot de v14 y no se
/// puede validar la forma con `SchemaVerifier.migrateAndValidate`: ese
/// método abre la base AFIRMANDO que su versión objetivo es la que se le
/// pasa, así que con 13 desde v13 drift ve una base al día y no ejecuta
/// `onUpgrade`, y con 14 no hay snapshot que instanciar. Lo que importa acá
/// son los DATOS, y para eso la migración se dispara como en la app: se abre
/// `AppDatabase` sobre una base que sigue en v13 y la primera consulta la
/// migra.
///
/// Las filas se siembran sobre la base VIEJA (`schemaAt(13)` y las clases
/// generadas de esa versión), antes de abrirla con `AppDatabase`: así son
/// datos de antes de migrar de verdad.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedItem(v13.DatabaseAtV13 db, String id) async {
    await db
        .into(db.sources)
        .insert(
          v13.SourcesCompanion.insert(
            id: 'src-$id',
            kind: 'webPage',
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v13.ItemsCompanion.insert(
            id: id,
            title: 'Elemento $id',
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
  }

  Future<void> definition(
    v13.DatabaseAtV13 db,
    String id,
    String name, {
    bool system = false,
  }) => db
      .into(db.propertyDefinitions)
      .insert(
        v13.PropertyDefinitionsCompanion.insert(
          id: id,
          name: name,
          createdAt: seconds,
          type: const Value('text'),
          // El snapshot guarda los booleanos como enteros.
          isSystem: Value(system ? 1 : 0),
        ),
      );

  Future<void> value(
    v13.DatabaseAtV13 db,
    String id,
    String definitionId,
    String label,
  ) => db
      .into(db.propertyValues)
      .insert(
        v13.PropertyValuesCompanion.insert(
          id: id,
          definitionId: definitionId,
          value: label,
          createdAt: seconds,
        ),
      );

  Future<void> assign(v13.DatabaseAtV13 db, String itemId, String valueId) => db
      .into(db.itemPropertyValues)
      .insert(
        v13.ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
        ),
      );

  Future<void> tag(v13.DatabaseAtV13 db, String id, String name) => db
      .into(db.tags)
      .insert(v13.TagsCompanion.insert(id: id, name: name, createdAt: seconds));

  Future<void> tagItem(v13.DatabaseAtV13 db, String itemId, String tagId) => db
      .into(db.itemTags)
      .insert(v13.ItemTagsCompanion.insert(itemId: itemId, tagId: tagId));

  /// Una bóveda como la deja la app de antes de F8:
  ///  * "Filosofía": F2 la copió a Tema (con OTRO id que la etiqueta) y se
  ///    quedó al día;
  ///  * "Roma": etiqueta creada después de F2, nunca llegó a Tema;
  ///  * "Canción": la etiqueta y el valor de Tema difieren en el acento;
  ///  * "Suelto": un valor de Tema que ninguna etiqueta reclama;
  ///  * "Región: Roma": otra categoría con el mismo texto que una etiqueta.
  Future<void> seedPreF8Vault(v13.DatabaseAtV13 db) async {
    for (final id in ['i1', 'i2', 'i3']) {
      await seedItem(db, id);
    }
    await definition(db, 'def-tema', 'Tema', system: true);
    await definition(db, 'def-region', 'Región');

    await value(db, 'v-fil', 'def-tema', 'Filosofía');
    await assign(db, 'i1', 'v-fil');
    await value(db, 'v-cancion', 'def-tema', 'Cancion');
    await assign(db, 'i3', 'v-cancion');
    await value(db, 'v-suelto', 'def-tema', 'Suelto');
    await assign(db, 'i2', 'v-suelto');
    await value(db, 'v-region-roma', 'def-region', 'Roma');
    await assign(db, 'i1', 'v-region-roma');

    await tag(db, 't-fil', 'Filosofía');
    await tagItem(db, 'i1', 't-fil');
    await tagItem(db, 'i2', 't-fil');
    await tag(db, 't-roma', 'Roma');
    await tagItem(db, 'i1', 't-roma');
    await tagItem(db, 'i2', 't-roma');
    await tag(db, 't-cancion', 'Canción');
    await tagItem(db, 'i3', 't-cancion');
  }

  /// Deja una base en v13 con lo que siembre [seed], y la migra a 14 abriendo
  /// `AppDatabase` encima.
  Future<AppDatabase> migrateFrom13({
    Future<void> Function(v13.DatabaseAtV13 oldDb)? seed,
  }) async {
    final schema = await verifier.schemaAt(13);
    final oldDb = v13.DatabaseAtV13(schema.newConnection());
    if (seed != null) await seed(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    // Abrir la base es lo que dispara la migración de 13 a 14.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  Future<Set<(String, String)>> temaPairs(AppDatabase db) async {
    final rows = await (db.select(db.itemPropertyValues).join([
      innerJoin(
        db.propertyValues,
        db.propertyValues.id.equalsExp(db.itemPropertyValues.propertyValueId),
      ),
    ])..where(db.propertyValues.definitionId.equals('def-tema'))).get();
    return {
      for (final row in rows)
        (
          row.readTable(db.itemPropertyValues).itemId,
          normalizeVocabularyLabel(row.readTable(db.propertyValues).value),
        ),
    };
  }

  test('migrar de v13 a v14 une las etiquetas con Tema, sin perder ninguna '
      'asignación', () async {
    final db = await migrateFrom13(seed: seedPreF8Vault);

    // Lo que TENÍA cada elemento antes: sus etiquetas y sus valores de
    // Tema, por texto normalizado.
    final expected = {
      ('i1', 'filosofia'),
      ('i2', 'filosofia'),
      ('i1', 'roma'),
      ('i2', 'roma'),
      ('i3', 'cancion'),
      ('i2', 'suelto'),
    };
    expect(await temaPairs(db), expected);

    final values = await (db.select(
      db.propertyValues,
    )..where((v) => v.definitionId.equals('def-tema'))).get();
    expect(values.map((v) => v.value).toSet(), {
      'Filosofía',
      'Roma',
      'Cancion',
      'Suelto',
    });
    // Filosofía y Canción reusaron el valor que ya había; Roma, que nunca
    // llegó a Tema, se creó con el id de su etiqueta.
    expect(values.map((v) => v.id).toSet(), {
      'v-fil',
      'v-cancion',
      'v-suelto',
      't-roma',
    });
  });

  test(
    'la etiqueta con otro acento queda como alias del valor existente',
    () async {
      final db = await migrateFrom13(seed: seedPreF8Vault);

      final aliases = await db.select(db.propertyAliases).get();
      expect(aliases.map((a) => (a.propertyValueId, a.alias)), [
        ('v-cancion', 'Canción'),
      ]);
    },
  );

  test('otras categorías, Tags e ItemTags quedan intactas', () async {
    final db = await migrateFrom13(seed: seedPreF8Vault);

    // "Región: Roma" sigue siendo suyo, no se mezcló con la etiqueta.
    final regionValue = await (db.select(
      db.propertyValues,
    )..where((v) => v.id.equals('v-region-roma'))).getSingle();
    expect(regionValue.definitionId, 'def-region');
    final regionAssignments = await (db.select(
      db.itemPropertyValues,
    )..where((a) => a.propertyValueId.equals('v-region-roma'))).get();
    expect(regionAssignments.map((a) => a.itemId), ['i1']);
    // Las tablas viejas no se tocan: las retira F10.
    expect(await db.select(db.tags).get(), hasLength(3));
    expect(await db.select(db.itemTags).get(), hasLength(5));
  });

  test('deja el informe de lo que unió en MigrationIssues', () async {
    final db = await migrateFrom13(seed: seedPreF8Vault);

    final report = await (db.select(
      db.migrationIssues,
    )..where((i) => i.migration.equals('f8_tag_reconciliation'))).get();
    expect(report.map((r) => (r.stage, r.itemId)), [('orphan_tag', 't-roma')]);
  });

  test('una bóveda sin etiquetas migra sin escribir nada', () async {
    final db = await migrateFrom13(seed: (oldDb) => seedItem(oldDb, 'i1'));

    expect(await db.select(db.migrationIssues).get(), isEmpty);
    // Solo las dos categorías de sistema que siembra la migración.
    final definitions = await db.select(db.propertyDefinitions).get();
    expect(definitions.map((d) => d.name).toSet(), {'Tema', 'Fecha del hecho'});
    expect(await db.select(db.propertyValues).get(), isEmpty);
  });
}
