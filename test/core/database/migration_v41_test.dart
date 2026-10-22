import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v40.dart' as v40;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 40→41: un elemento en uno o varios temas (F37,
/// decisión 80). El tema deja de ser la columna `item.space_id` y pasa a la
/// tabla `item_spaces`; cada elemento que estaba en un tema queda en él, y
/// `item` se reconstruye sin la columna. Nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v40.DatabaseAtV40 db) async {
    // Como una bóveda de verdad: con su índice de texto, que no es parte del
    // esquema de drift.
    await db.customStatement(createSearchTable);
    for (final trigger in searchTriggers) {
      await db.customStatement(trigger);
    }
    for (final (id, name) in [('historia', 'Historia'), ('arte', 'Arte')]) {
      await db.customStatement(
        'INSERT INTO spaces (id, name, created_at) '
        "VALUES ('$id', '$name', $seconds)",
      );
    }
    for (final (id, title, space) in [
      ('a', 'La Revolución de Mayo', "'historia'"),
      ('b', 'Sin tema', 'NULL'),
      ('c', 'El Renacimiento', "'arte'"),
    ]) {
      await db.customStatement(
        'INSERT INTO item (id, title, space_id, kind, state, created_at, '
        "updated_at, device_id) VALUES ('$id', '$title', $space, 'note', "
        "'processed', $seconds, $seconds, 'dispositivo-a')",
      );
    }
    // Un tema que ya no existe: una base vieja pudo quedar así si se borró
    // con las claves foráneas apagadas.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
      'INSERT INTO item (id, title, space_id, kind, state, created_at, '
      "updated_at, device_id) VALUES ('d', 'Huérfano', 'borrado', 'note', "
      "'processed', $seconds, $seconds, 'dispositivo-a')",
    );
  }

  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
    ...VaultCounts.viewsAndTemplatesTables,
    ...VaultCounts.notebookTables,
    ...VaultCounts.habitTables,
    ...VaultCounts.quizTables,
    ...VaultCounts.aiTables,
    ...VaultCounts.aiFieldChangeTables,
    ...VaultCounts.contentTrashTables,
    ...VaultCounts.studyTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom40({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(40);
    final oldDb = v40.DatabaseAtV40(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<Set<(String, String)>> placements(AppDatabase db) async => {
    for (final row in await db.select(db.itemSpaces).get())
      (row.itemId, row.spaceId),
  };

  test('la migración llega a la forma del snapshot de v41', () async {
    await migrateFrom40();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(41));
  });

  test('cada elemento queda en el tema en que estaba; uno sin tema, o con un '
      'tema que ya no existe, queda sin ninguno', () async {
    final db = await migrateFrom40();

    expect(await placements(db), {('a', 'historia'), ('c', 'arte')});
    final columns = await db.customSelect('PRAGMA table_info(item)').get();
    expect([
      for (final c in columns) c.read<String>('name'),
    ], isNot(contains('space_id')));
    final indexes = {
      for (final row
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
        row.read<String>('name'),
    };
    expect(indexes, contains('idx_item_spaces_space'));
    expect(indexes, isNot(contains('idx_knowledge_entries_space')));
  });

  test('un elemento puede estar en varios temas, en cada uno una vez, y su '
      'fila se va con él o con el tema', () async {
    final db = await migrateFrom40();

    await db
        .into(db.itemSpaces)
        .insert(ItemSpacesCompanion.insert(itemId: 'a', spaceId: 'arte'));
    await expectLater(
      db
          .into(db.itemSpaces)
          .insert(ItemSpacesCompanion.insert(itemId: 'a', spaceId: 'arte')),
      throwsA(isA<Object>()),
    );
    expect(await placements(db), {
      ('a', 'historia'),
      ('a', 'arte'),
      ('c', 'arte'),
    });

    await db.customStatement("DELETE FROM spaces WHERE id = 'arte'");
    expect(await placements(db), {('a', 'historia')});
    expect(
      await db.customSelect("SELECT 1 FROM item WHERE id = 'c'").get(),
      hasLength(1),
    );

    await db.customStatement("DELETE FROM item WHERE id = 'a'");
    expect(await placements(db), isEmpty);
  });

  test('el índice de texto sigue entero y sigue al día', () async {
    final db = await migrateFrom40();

    Future<List<String>> search(String term) async => [
      for (final row
          in await db
              .customSelect(
                'SELECT item_id FROM item_search WHERE item_search MATCH ?',
                variables: [Variable<String>(term)],
              )
              .get())
        row.read<String>('item_id'),
    ];

    expect(await search('Revolución'), ['a']);
    // Los triggers de la tabla reconstruida siguen andando.
    await db.customStatement(
      "UPDATE item SET title = 'El Barroco' WHERE id = 'c'",
    );
    expect(await search('Barroco'), ['c']);
    expect(await search('Renacimiento'), isEmpty);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom40(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
