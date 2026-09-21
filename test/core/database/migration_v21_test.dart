import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/database/vocabulary_hierarchy.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v20.dart' as v20;
import '../../support/migration_counts.dart';
import '../../support/schema_snapshot.dart';

/// La migración de esquema 20→21 —la jerarquía del vocabulario (F13)—: un valor
/// de propiedad gana un padre y una profundidad.
///
/// Es aditiva: dos columnas, un índice y cuatro triggers. Se siembra la base de
/// v20 (con `schemaAt(20)` y las clases generadas de esa versión) y recién
/// después se abre `AppDatabase` encima. Lo que se comprueba es que no cambia
/// ninguna fila de nada de lo que había, que todo valor queda en la raíz, y que
/// las reglas de la jerarquía quedan en la base migrada igual que en una nueva.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.
  const article = 'La república romana.\n\nEl imperio.';

  /// Una bóveda como la deja v20: una fuente con su texto y sus chunks, una
  /// nota, y un vocabulario con tres categorías, cuatro valores y tres
  /// asignaciones.
  Future<void> seedVault(v20.DatabaseAtV20 db) async {
    for (final (id, kind, isNote) in [
      ('art', 'webPage', false),
      ('nota', 'manualNote', true),
    ]) {
      await db
          .into(db.item)
          .insert(
            v20.ItemCompanion.insert(
              id: id,
              title: 'Elemento $id',
              kind: isNote ? 'note' : 'source',
              state: 'processed',
              createdAt: seconds,
              updatedAt: seconds,
              deviceId: 'dispositivo-a',
            ),
          );
      if (isNote) {
        await db
            .into(db.note)
            .insert(
              v20.NoteCompanion.insert(
                itemId: id,
                noteKind: 'living',
                maturity: 'seed',
              ),
            );
      } else {
        await db
            .into(db.source)
            .insert(
              v20.SourceCompanion.insert(
                itemId: id,
                sourceType: kind,
                capturedAt: seconds,
                contentHash: '',
                processingStatus: 'done',
              ),
            );
      }
    }
    await db
        .into(db.renditions)
        .insert(
          v20.RenditionsCompanion.insert(
            id: 'r-art',
            itemId: 'art',
            kind: 'markdown',
            content: const Value(article),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
    for (final (seq, start, end, content) in [
      (0, 0, 22, 'La república romana.\n\n'),
      (1, 22, 33, 'El imperio.'),
    ]) {
      await db
          .into(db.chunks)
          .insert(
            v20.ChunksCompanion.insert(
              id: 'chunk-art-$seq',
              itemId: 'art',
              seq: seq,
              content: content,
              charStart: start,
              charEnd: end,
            ),
          );
    }
    for (final (id, name, type, system) in [
      ('def-tema', 'Tema', 'text', 1),
      ('def-epoca', 'Época', 'text', 0),
      ('def-fecha', 'Fecha del hecho', 'date', 1),
    ]) {
      await db
          .into(db.propertyDefinitions)
          .insert(
            v20.PropertyDefinitionsCompanion.insert(
              id: id,
              name: name,
              createdAt: seconds,
              type: Value(type),
              isSystem: Value(system),
            ),
          );
    }
    for (final (id, definition, label) in [
      ('roma', 'def-tema', 'Roma'),
      ('republica', 'def-tema', 'Roma republicana'),
      ('antigua', 'def-epoca', 'Antigua'),
      ('44', 'def-fecha', '44 a.C.'),
    ]) {
      await db
          .into(db.propertyValues)
          .insert(
            v20.PropertyValuesCompanion.insert(
              id: id,
              definitionId: definition,
              value: label,
              createdAt: seconds,
            ),
          );
    }
    for (final (item, value) in [
      ('art', 'roma'),
      ('art', 'republica'),
      ('nota', 'roma'),
    ]) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            v20.ItemPropertyValuesCompanion.insert(
              itemId: item,
              propertyValueId: value,
            ),
          );
    }
  }

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in [
      ...VaultCounts.userDataTables,
      ...VaultCounts.modelTables,
    ])
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom20({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(20);
    final oldDb = v20.DatabaseAtV20(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<Set<String>> namesOf(AppDatabase db, String sql) async => {
    for (final r in await db.customSelect(sql).get()) r.read<String>('name'),
  };

  test('la migración llega a la forma del snapshot de v21', () async {
    await migrateFrom20();
    // `migrateAndValidate` ya comparó el esquema contra el snapshot.
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(21));
  });

  group('lo que había', () {
    test('no cambia ninguna fila de ninguna tabla', () async {
      final before = <String, int>{};
      final db = await migrateFrom20(countsBefore: before);

      expect(withoutAuthorCategory(await countsOf(db)), before);
      // Y no es una comparación de ceros.
      expect(before['item'], 2);
      expect(before['property_values'], 4);
      expect(before['item_property_values'], 3);
      expect(before['chunks'], 2);
    });

    test('todo valor queda en la raíz, con su texto y su categoría', () async {
      final db = await migrateFrom20();

      final rows = await (db.select(
        db.propertyValues,
      )..orderBy([(v) => OrderingTerm.asc(v.id)])).get();

      expect(rows.map((v) => v.id), ['44', 'antigua', 'republica', 'roma']);
      for (final row in rows) {
        expect(row.parentId, isNull, reason: row.value);
        expect(row.depth, 0, reason: row.value);
      }
      final republica = rows.firstWhere((v) => v.id == 'republica');
      expect(republica.value, 'Roma republicana');
      expect(republica.definitionId, 'def-tema');
    });

    test('lo asignado sigue asignado', () async {
      final db = await migrateFrom20();

      final assigned = await db
          .customSelect(
            'SELECT item_id, property_value_id FROM item_property_values '
            'ORDER BY item_id, property_value_id',
          )
          .get();

      expect(
        [
          for (final r in assigned)
            (r.read<String>('item_id'), r.read<String>('property_value_id')),
        ],
        [('art', 'republica'), ('art', 'roma'), ('nota', 'roma')],
      );
    });

    test('el texto de la fuente y sus chunks quedan exactos', () async {
      final db = await migrateFrom20();

      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();

      expect(rendition.content, article);
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('; '));
      expect(report.chunksChecked, 2);
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      final db = await migrateFrom20();

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('lo nuevo', () {
    test('las columnas, con su valor por omisión y su tope', () async {
      final db = await migrateFrom20();

      final columns = {
        for (final r
            in await db
                .customSelect(
                  "SELECT * FROM pragma_table_info('property_values')",
                )
                .get())
          r.read<String>('name'): r,
      };

      expect(columns['parent_id']!.read<int>('notnull'), 0);
      expect(columns['depth']!.read<int>('notnull'), 1);
      expect(columns['depth']!.read<String>('dflt_value'), '0');
      // El tope está en la propia tabla, no solo en el código.
      final sql =
          (await db
                  .customSelect(
                    'SELECT sql FROM sqlite_master '
                    "WHERE name = 'property_values'",
                  )
                  .getSingle())
              .read<String>('sql');
      expect(sql, matches(RegExp(r'CHECK\s*\("?depth"?\s+BETWEEN 0 AND 4\)')));
    });

    test('el índice del padre existe', () async {
      final db = await migrateFrom20();

      final indexes = await namesOf(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(indexes, contains('idx_property_values_parent'));
    });

    test('la clave del padre apunta al mismo vocabulario', () async {
      final db = await migrateFrom20();

      final targets = {
        for (final r
            in await db
                .customSelect(
                  'SELECT "from", "table", on_delete '
                  "FROM pragma_foreign_key_list('property_values')",
                )
                .get())
          r.read<String>('from'): (
            r.read<String>('table'),
            r.read<String>('on_delete'),
          ),
      };

      expect(targets['parent_id'], ('property_values', 'SET NULL'));
      expect(targets['definition_id']!.$1, 'property_definitions');
    });

    test('los triggers de la jerarquía existen', () async {
      final db = await migrateFrom20();

      final triggers = await namesOf(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'trigger'",
      );

      expect(triggers, containsAll(vocabularyHierarchyTriggerNames));
    });
  });

  group('las reglas valen en una base migrada, igual que en una nueva', () {
    test('un valor viejo puede recibir un padre de su categoría', () async {
      final db = await migrateFrom20();

      await db.customStatement(
        "UPDATE property_values SET parent_id = 'roma', depth = 1 "
        "WHERE id = 'republica'",
      );

      final row = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals('republica'))).getSingle();
      expect((row.parentId, row.depth), ('roma', 1));
    });

    test('un ciclo se rechaza', () async {
      final db = await migrateFrom20();
      await db.customStatement(
        "UPDATE property_values SET parent_id = 'roma', depth = 1 "
        "WHERE id = 'republica'",
      );

      await expectLater(
        db.customStatement(
          'UPDATE property_values SET parent_id = '
          "'republica' WHERE id = 'roma'",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('un padre de otra categoría se rechaza', () async {
      final db = await migrateFrom20();

      await expectLater(
        db.customStatement(
          "UPDATE property_values SET parent_id = 'roma', depth = 1 "
          "WHERE id = 'antigua'",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('una categoría de fecha no admite padre', () async {
      final db = await migrateFrom20();
      await db.customStatement(
        'INSERT INTO property_values (id, definition_id, value, created_at) '
        "VALUES ('43', 'def-fecha', '43 a.C.', $seconds)",
      );

      await expectLater(
        db.customStatement(
          "UPDATE property_values SET parent_id = '44', depth = 1 "
          "WHERE id = '43'",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
