import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v31.dart' as v31;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 31→32 —el idioma del original (F22)—: una
/// columna nueva en `source`, nula en todo lo de antes ("no se sabe": un
/// audio se sigue transcribiendo en español). Aditiva: ninguna fila cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v31.DatabaseAtV31 db) async {
    // El esquema v31 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('alabanza', 'Alabanza', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO source (item_id, source_type, author_name, captured_at, '
      "content_hash, processing_status) VALUES ('alabanza', 'audio', "
      "'Un coro', $seconds, 'hash', 'done')",
    );
    // Un chunk de un libro con una palabra cortada al final del renglón.
    await db.customStatement(
      'INSERT INTO chunks (id, item_id, seq, content, char_start, char_end) '
      "VALUES ('c1', 'alabanza', 0, 'las ex-' || char(10) || 'plicaciones', "
      '0, 19)',
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom31({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(31);
    final oldDb = v31.DatabaseAtV31(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v32', () async {
    await migrateFrom31();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(32));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom31(countsBefore: before);

    expect(await countsOf(db), before);
    expect(before['item'], 1);
  });

  test('lo de antes queda sin idioma, con el resto de la fuente intacto, y '
      'el idioma se puede guardar después', () async {
    final db = await migrateFrom31();

    final row = await db.select(db.knowledgeSources).getSingle();
    expect(row.language, isNull);
    expect(row.authorName, 'Un coro');

    await (db.update(db.knowledgeSources)
          ..where((s) => s.itemId.equals('alabanza')))
        .write(const KnowledgeSourcesCompanion(language: Value('en')));
    expect((await db.select(db.knowledgeSources).getSingle()).language, 'en');
  });

  test('el índice de los chunks queda rehecho: encuentra la palabra cortada '
      'por guion de lo que ya estaba', () async {
    final db = await migrateFrom31();

    final found = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM chunk_search '
          "WHERE chunk_search MATCH 'explicaciones'",
        )
        .getSingle();
    expect(found.read<int>('n'), 1);
    await db.customStatement(
      "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
    );
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom31();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
