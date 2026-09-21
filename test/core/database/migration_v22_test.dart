import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/migrations/seed_author_category_v22.dart';
import 'package:sinapsis/core/database/reference_triggers.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v21.dart' as v21;
import '../../support/fake_id_generator.dart';
import '../../support/schema_snapshot.dart';

/// La migración de esquema 21→22 —la biblioteca académica (F15)—: los datos
/// bibliográficos de una fuente, sus personas, el nombre partido en el
/// vocabulario y la categoría de sistema «Autor».
///
/// Es aditiva: dos tablas, cuatro columnas nulas, tres índices y cuatro
/// triggers. Se siembra la base de v21 (con `schemaAt(21)` y las clases
/// generadas de esa versión) y recién después se abre `AppDatabase` encima. Lo
/// que se comprueba es que no cambia ninguna fila de lo que había, que la
/// categoría «Autor» queda como debe —también cuando alguien ya tenía una con
/// ese nombre— y que las reglas de las referencias quedan en la base migrada.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.
  const article = 'La república romana.\n\nEl imperio.';

  /// Una bóveda como la deja v21: una fuente con su texto y sus chunks, una
  /// nota, y un vocabulario con tres categorías, cuatro valores —uno bajo otro,
  /// que es lo que v21 permite— y tres asignaciones.
  Future<void> seedVault(v21.DatabaseAtV21 db) async {
    for (final (id, kind, isNote) in [
      ('art', 'webPage', false),
      ('nota', 'manualNote', true),
    ]) {
      await db
          .into(db.item)
          .insert(
            v21.ItemCompanion.insert(
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
              v21.NoteCompanion.insert(
                itemId: id,
                noteKind: 'living',
                maturity: 'seed',
              ),
            );
      } else {
        await db
            .into(db.source)
            .insert(
              v21.SourceCompanion.insert(
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
          v21.RenditionsCompanion.insert(
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
            v21.ChunksCompanion.insert(
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
            v21.PropertyDefinitionsCompanion.insert(
              id: id,
              name: name,
              createdAt: seconds,
              type: Value(type),
              isSystem: Value(system),
            ),
          );
    }
    for (final (id, definition, label, parent) in [
      ('roma', 'def-tema', 'Roma', null),
      ('republica', 'def-tema', 'Roma republicana', 'roma'),
      ('antigua', 'def-epoca', 'Antigua', null),
      ('44', 'def-fecha', '44 a.C.', null),
    ]) {
      await db
          .into(db.propertyValues)
          .insert(
            v21.PropertyValuesCompanion.insert(
              id: id,
              definitionId: definition,
              value: label,
              createdAt: seconds,
              parentId: Value(parent),
              depth: Value(parent == null ? 0 : 1),
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
            v21.ItemPropertyValuesCompanion.insert(
              itemId: item,
              propertyValueId: value,
            ),
          );
    }
  }

  /// Las tablas que la migración no debe cambiar de tamaño.
  final untouched = [
    ...VaultCounts.userDataTables.where((t) => t != 'property_definitions'),
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in [...untouched, 'property_definitions'])
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  /// Migra una bóveda de v21. [extra] agrega lo que cada prueba necesite antes
  /// de migrar, sobre la bóveda de siempre.
  Future<AppDatabase> migrateFrom21({
    Future<void> Function(v21.DatabaseAtV21 db)? extra,
    Map<String, int>? countsBefore,
  }) async {
    final schema = await verifier.schemaAt(21);
    final oldDb = v21.DatabaseAtV21(schema.newConnection());
    await seedVault(oldDb);
    await extra?.call(oldDb);
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

  /// Las categorías llamadas «Autor» —sin distinguir mayúsculas—, con lo que
  /// importa de cada una.
  Future<List<({String id, String name, String type, bool system})>> authors(
    AppDatabase db,
  ) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT id, name, type, is_system FROM property_definitions '
              "WHERE lower(name) = 'autor' ORDER BY id",
            )
            .get())
      (
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        type: r.read<String>('type'),
        system: r.read<int>('is_system') == 1,
      ),
  ];

  Future<List<Map<String, Object?>>> issuesOf(AppDatabase db) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT migration, item_id, stage, message '
              'FROM migration_issues ORDER BY item_id, stage',
            )
            .get())
      {
        'migration': r.read<String>('migration'),
        'item_id': r.read<String>('item_id'),
        'stage': r.read<String>('stage'),
        'message': r.read<String>('message'),
      },
  ];

  test('la migración llega a la forma del snapshot de v22', () async {
    await migrateFrom21();
    // `migrateAndValidate` ya comparó el esquema contra el snapshot.
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(22));
  });

  group('lo que había', () {
    test('no cambia ninguna fila de nada, salvo la categoría nueva', () async {
      final before = <String, int>{};
      final db = await migrateFrom21(countsBefore: before);
      final after = await countsOf(db);

      expect(
        {...after}..remove('property_definitions'),
        {...before}..remove('property_definitions'),
      );
      expect(before['property_definitions'], 3);
      expect(after['property_definitions'], 4);
      // Y no es una comparación de ceros.
      expect(before['item'], 2);
      expect(before['property_values'], 4);
      expect(before['item_property_values'], 3);
      expect(before['chunks'], 2);
    });

    test('no anota ningún problema en una bóveda limpia', () async {
      final db = await migrateFrom21();

      expect(await issuesOf(db), isEmpty);
    });

    test('la jerarquía de «Tema» queda como estaba', () async {
      final db = await migrateFrom21();

      final rows = {
        for (final r
            in await db
                .customSelect(
                  'SELECT id, parent_id, depth FROM property_values',
                )
                .get())
          r.read<String>('id'): (
            r.readNullable<String>('parent_id'),
            r.read<int>('depth'),
          ),
      };

      expect(rows['republica'], ('roma', 1));
      expect(rows['roma'], (null, 0));
    });

    test('lo asignado sigue asignado', () async {
      final db = await migrateFrom21();

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
      final db = await migrateFrom21();

      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();

      expect(rendition.content, article);
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('; '));
      expect(report.chunksChecked, 2);
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      final db = await migrateFrom21();

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('lo nuevo', () {
    test('las tablas nuevas existen y empiezan vacías', () async {
      final db = await migrateFrom21();

      for (final table in VaultCounts.referenceTables) {
        final n = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(n.read<int>('n'), 0, reason: table);
      }
    });

    test('la referencia tiene sus columnas, todas opcionales', () async {
      final db = await migrateFrom21();

      final columns = {
        for (final r
            in await db
                .customSelect(
                  "SELECT * FROM pragma_table_info('source_reference')",
                )
                .get())
          r.read<String>('name'): r.read<int>('notnull'),
      };

      expect(columns.keys, {
        'item_id',
        'reference_type',
        'container_title',
        'publisher',
        'publisher_place',
        'edition',
        'volume',
        'issue',
        'pages',
        'isbn',
        'issn',
        'doi',
        'accessed_at',
        'citation_key',
        'publication_precision',
      });
      expect(columns['item_id'], 1);
      // Nada más es obligatorio: una fuente sin datos se cita con lo que hay.
      for (final entry in columns.entries.where((e) => e.key != 'item_id')) {
        expect(entry.value, 0, reason: entry.key);
      }
    });

    test('las columnas de la persona son nulas en todo lo que había', () async {
      final db = await migrateFrom21();

      final rows = await db
          .customSelect(
            'SELECT name_family, name_given, name_suffix, is_institution '
            'FROM property_values',
          )
          .get();

      expect(rows, hasLength(4));
      for (final r in rows) {
        expect(r.readNullable<String>('name_family'), isNull);
        expect(r.readNullable<String>('name_given'), isNull);
        expect(r.readNullable<String>('name_suffix'), isNull);
        expect(r.readNullable<int>('is_institution'), isNull);
      }
    });

    test(
      'las claves de las personas se van con la obra y con el valor',
      () async {
        final db = await migrateFrom21();

        final targets = {
          for (final r
              in await db
                  .customSelect(
                    'SELECT "from", "table", on_delete '
                    "FROM pragma_foreign_key_list('source_contributor')",
                  )
                  .get())
            r.read<String>('from'): (
              r.read<String>('table'),
              r.read<String>('on_delete'),
            ),
        };

        expect(targets['item_id'], ('item', 'CASCADE'));
        expect(targets['property_value_id'], ('property_values', 'CASCADE'));
      },
    );

    test('los índices existen', () async {
      final db = await migrateFrom21();

      final indexes = await namesOf(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(
        indexes,
        containsAll([
          'idx_source_reference_doi',
          'idx_source_reference_isbn',
          'idx_source_contributor_person',
        ]),
      );
    });

    test('los triggers de las referencias existen', () async {
      final db = await migrateFrom21();

      final triggers = await namesOf(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'trigger'",
      );

      expect(triggers, containsAll(referenceTriggerNames));
    });
  });

  group('la categoría «Autor»', () {
    test('en una bóveda sin ella se crea, de sistema y de persona', () async {
      final db = await migrateFrom21();

      final found = await authors(db);

      expect(found, hasLength(1));
      expect(found.single.name, 'Autor');
      expect(found.single.type, 'person');
      expect(found.single.system, isTrue);
    });

    test(
      'si alguien ya tenía una de texto se REUSA, con todo lo suyo',
      () async {
        final db = await migrateFrom21(
          extra: (old) async {
            await old
                .into(old.propertyDefinitions)
                .insert(
                  v21.PropertyDefinitionsCompanion.insert(
                    id: 'def-autor',
                    name: 'Autor',
                    createdAt: seconds,
                  ),
                );
            for (final (id, label) in [
              ('borges', 'Borges, Jorge Luis'),
              ('cortazar', 'Cortázar, Julio'),
            ]) {
              await old
                  .into(old.propertyValues)
                  .insert(
                    v21.PropertyValuesCompanion.insert(
                      id: id,
                      definitionId: 'def-autor',
                      value: label,
                      createdAt: seconds,
                    ),
                  );
            }
            await old
                .into(old.itemPropertyValues)
                .insert(
                  v21.ItemPropertyValuesCompanion.insert(
                    itemId: 'art',
                    propertyValueId: 'borges',
                  ),
                );
          },
        );

        final found = await authors(db);
        expect(found, hasLength(1));
        // La misma categoría de antes, no una copia.
        expect(found.single.id, 'def-autor');
        expect(found.single.type, 'person');
        expect(found.single.system, isTrue);
        // Sin categoría nueva: eran 4 con la suya, y siguen siendo 4.
        expect((await countsOf(db))['property_definitions'], 4);
        // Y sus valores, con lo que tenían asignado y SIN nombre estructurado:
        // no se adivina dónde termina el apellido.
        final values = await db
            .customSelect(
              'SELECT id, name_family FROM property_values '
              "WHERE definition_id = 'def-autor' ORDER BY id",
            )
            .get();
        expect(
          [for (final r in values) r.read<String>('id')],
          ['borges', 'cortazar'],
        );
        for (final r in values) {
          expect(r.readNullable<String>('name_family'), isNull);
        }
        final assigned = await db
            .customSelect(
              'SELECT property_value_id FROM item_property_values '
              "WHERE property_value_id = 'borges'",
            )
            .get();
        expect(assigned, hasLength(1));
        expect(await issuesOf(db), isEmpty);
      },
    );

    test('con otras mayúsculas también se reusa', () async {
      final db = await migrateFrom21(
        extra: (old) => old
            .into(old.propertyDefinitions)
            .insert(
              v21.PropertyDefinitionsCompanion.insert(
                id: 'def-autor',
                name: 'autor',
                createdAt: seconds,
              ),
            ),
      );

      final found = await authors(db);

      expect(found, hasLength(1));
      expect(found.single.id, 'def-autor');
      expect(found.single.system, isTrue);
    });

    test('una jerarquía no cabe en las personas: los hijos suben a la raíz y '
        'queda anotado', () async {
      final db = await migrateFrom21(
        extra: (old) async {
          await old
              .into(old.propertyDefinitions)
              .insert(
                v21.PropertyDefinitionsCompanion.insert(
                  id: 'def-autor',
                  name: 'Autor',
                  createdAt: seconds,
                ),
              );
          await old
              .into(old.propertyValues)
              .insert(
                v21.PropertyValuesCompanion.insert(
                  id: 'boom',
                  definitionId: 'def-autor',
                  value: 'Boom latinoamericano',
                  createdAt: seconds,
                ),
              );
          await old
              .into(old.propertyValues)
              .insert(
                v21.PropertyValuesCompanion.insert(
                  id: 'cortazar',
                  definitionId: 'def-autor',
                  value: 'Cortázar, Julio',
                  createdAt: seconds,
                  parentId: const Value('boom'),
                  depth: const Value(1),
                ),
              );
        },
      );

      final rows = {
        for (final r
            in await db
                .customSelect(
                  'SELECT id, parent_id, depth FROM property_values '
                  "WHERE definition_id = 'def-autor'",
                )
                .get())
          r.read<String>('id'): (
            r.readNullable<String>('parent_id'),
            r.read<int>('depth'),
          ),
      };
      expect(rows, {'boom': (null, 0), 'cortazar': (null, 0)});

      final issues = await issuesOf(db);
      expect(issues, hasLength(1));
      expect(issues.single['migration'], authorCategoryMigration);
      expect(issues.single['item_id'], 'cortazar');
      expect(issues.single['stage'], 'flatten_hierarchy');
      // Dice cuál era su padre, para poder rehacerlo a mano.
      expect(issues.single['message'], contains('Boom latinoamericano'));
      // Lo de «Tema» no se tocó.
      final republica = await db
          .customSelect(
            "SELECT parent_id FROM property_values WHERE id = 'republica'",
          )
          .getSingle();
      expect(republica.read<String>('parent_id'), 'roma');
    });

    for (final type in ['date', 'number']) {
      test('una de $type no puede ser la de las personas: se aparta con otro '
          'nombre y se crea la de sistema', () async {
        final db = await migrateFrom21(
          extra: (old) async {
            await old
                .into(old.propertyDefinitions)
                .insert(
                  v21.PropertyDefinitionsCompanion.insert(
                    id: 'def-autor',
                    name: 'Autor',
                    createdAt: seconds,
                    type: Value(type),
                  ),
                );
            await old
                .into(old.propertyValues)
                .insert(
                  v21.PropertyValuesCompanion.insert(
                    id: 'v-autor',
                    definitionId: 'def-autor',
                    value: '1899',
                    createdAt: seconds,
                    numberValue: const Value(1899),
                    dateFromYear: const Value(1899),
                  ),
                );
          },
        );

        final found = await authors(db);
        expect(found, hasLength(1));
        expect(found.single.name, 'Autor');
        expect(found.single.type, 'person');
        expect(found.single.id, isNot('def-autor'));

        final apartada = await db
            .customSelect(
              'SELECT name, type, is_system FROM property_definitions '
              "WHERE id = 'def-autor'",
            )
            .getSingle();
        expect(apartada.read<String>('name'), 'Autor (anterior)');
        expect(apartada.read<String>('type'), type);
        expect(apartada.read<int>('is_system'), 0);
        // Con lo que tenía, intacto.
        final value = await db
            .customSelect(
              'SELECT number_value, date_from_year FROM property_values '
              "WHERE id = 'v-autor'",
            )
            .getSingle();
        expect(value.read<double>('number_value'), 1899);
        expect(value.read<int>('date_from_year'), 1899);

        expect((await countsOf(db))['property_definitions'], 5);
        final issues = await issuesOf(db);
        expect(issues, hasLength(1));
        expect(issues.single['stage'], 'category_renamed');
        expect(issues.single['item_id'], 'def-autor');
        expect(issues.single['message'], contains('Autor (anterior)'));
      });
    }

    test('si «Autor (anterior)» ya existe, prueba con otro número', () async {
      final db = await migrateFrom21(
        extra: (old) async {
          for (final (id, name) in [
            ('def-autor', 'Autor'),
            ('def-anterior', 'Autor (anterior)'),
          ]) {
            await old
                .into(old.propertyDefinitions)
                .insert(
                  v21.PropertyDefinitionsCompanion.insert(
                    id: id,
                    name: name,
                    createdAt: seconds,
                    type: const Value('date'),
                  ),
                );
          }
        },
      );

      final apartada = await db
          .customSelect(
            "SELECT name FROM property_definitions WHERE id = 'def-autor'",
          )
          .getSingle();
      expect(apartada.read<String>('name'), 'Autor (anterior 2)');
      expect(await authors(db), hasLength(1));
    });

    test('correrla otra vez no cambia nada', () async {
      final db = await migrateFrom21();
      final before = await authors(db);
      final definitions = (await countsOf(db))['property_definitions'];

      await ensureAuthorCategory(db, ids: FakeIdGenerator());

      expect(await authors(db), before);
      expect((await countsOf(db))['property_definitions'], definitions);
      expect(await issuesOf(db), isEmpty);
    });
  });

  group('las reglas valen en una base migrada', () {
    Future<String> authorCategory(AppDatabase db) async =>
        (await authors(db)).single.id;

    Future<void> personValue(AppDatabase db, String id) async {
      await db.customStatement(
        'INSERT INTO property_values '
        '(id, definition_id, value, created_at, name_family, name_given) '
        "VALUES ('$id', '${await authorCategory(db)}', "
        "'García Márquez, Gabriel', $seconds, 'García Márquez', 'Gabriel')",
      );
    }

    Matcher rejects(String reason) => throwsA(
      isA<SqliteException>().having(
        (e) => e.message,
        'mensaje',
        contains(reason),
      ),
    );

    test('una fuente puede tener una referencia y personas', () async {
      final db = await migrateFrom21();
      await personValue(db, 'gabo');

      await db.customStatement(
        'INSERT INTO source_reference (item_id, reference_type, doi) '
        "VALUES ('art', 'book', '10.1000/xyz')",
      );
      await db.customStatement(
        'INSERT INTO source_contributor '
        '(item_id, property_value_id, role, position) VALUES '
        "('art', 'gabo', 'author', 0)",
      );

      final row = await db
          .customSelect(
            'SELECT c.role, r.doi FROM source_contributor c '
            'JOIN source_reference r ON r.item_id = c.item_id',
          )
          .getSingle();
      expect(
        (row.read<String>('role'), row.read<String>('doi')),
        ('author', '10.1000/xyz'),
      );
    });

    test('una nota no tiene referencia ni personas', () async {
      final db = await migrateFrom21();
      await personValue(db, 'gabo');

      await expectLater(
        db.customStatement(
          "INSERT INTO source_reference (item_id) VALUES ('nota')",
        ),
        rejects('solo una fuente tiene referencia'),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO source_contributor '
          '(item_id, property_value_id, role, position) VALUES '
          "('nota', 'gabo', 'author', 0)",
        ),
        rejects('solo una fuente tiene personas'),
      );
    });

    test('un valor que no es una persona no es un autor', () async {
      final db = await migrateFrom21();

      await expectLater(
        db.customStatement(
          'INSERT INTO source_contributor '
          '(item_id, property_value_id, role, position) VALUES '
          "('art', 'roma', 'author', 0)",
        ),
        rejects('solo las personas son autores'),
      );
    });

    test(
      'cambiar a un autor por un valor que no es persona se rechaza',
      () async {
        final db = await migrateFrom21();
        await personValue(db, 'gabo');
        await db.customStatement(
          'INSERT INTO source_contributor '
          '(item_id, property_value_id, role, position) VALUES '
          "('art', 'gabo', 'author', 0)",
        );

        await expectLater(
          db.customStatement(
            "UPDATE source_contributor SET property_value_id = 'roma'",
          ),
          rejects('solo las personas son autores'),
        );
      },
    );

    test('un elemento o un valor que no existen los rechaza la clave, no la '
        'regla', () async {
      final db = await migrateFrom21();
      await personValue(db, 'gabo');

      await expectLater(
        db.customStatement(
          "INSERT INTO source_reference (item_id) VALUES ('fantasma')",
        ),
        rejects('FOREIGN KEY'),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO source_contributor '
          '(item_id, property_value_id, role, position) VALUES '
          "('art', 'fantasma', 'author', 0)",
        ),
        rejects('FOREIGN KEY'),
      );
    });
  });
}
