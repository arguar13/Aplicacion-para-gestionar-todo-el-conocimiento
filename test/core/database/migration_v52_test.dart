import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_search_text_backfill.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v51.dart' as v51;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 51→52 (F46, paso 5i): `chunks.search_text` —lo que
/// se busca de un chunk en Markdown, como se lee— y `search_text_rule`, y el
/// índice de los chunks sobre lo que se lee; las llena después, en segundo
/// plano, `ChunkSearchTextBackfill`. El texto de la Biblioteca no se toca.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  /// La página web que se vio en el emulador: la palabra está en la dirección
  /// de la foto y en un enlace con negrita.
  const page =
      'La planta crece.\n'
      '\n'
      '![](https://upload.wikimedia.org/wikipedia/commons/thumb/8/84/'
      'Fotosintesis_ox_ano.png)\n'
      '\n'
      'Sube debido a la [**fotosíntesis**](https://es.wikipedia.org/wiki/F) '
      'de las ex-\nplicaciones.';
  const pdf = 'Ver https://upload.wikimedia.org/foto.png en el anexo.';

  Future<void> seedVault(v51.DatabaseAtV51 db) async {
    for (final (id, type, file, text) in [
      ('web', 'webPage', null, page),
      ('libro', 'document', "'libros/anexo.pdf'", pdf),
      ('word', 'document', "'notas/tesis.docx'", 'Una [cita](https://x.org).'),
    ]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Fuente', 'source', 'triaged', $seconds, "
        "$seconds, 'dispositivo-a')",
      );
      await db.customStatement(
        'INSERT INTO source (item_id, source_type, captured_at, '
        'original_blob_path, content_hash, processing_status) VALUES '
        "('$id', '$type', $seconds, ${file ?? 'NULL'}, 'h', 'ready')",
      );
      await db.customStatement(
        'INSERT INTO renditions (id, item_id, kind, is_primary, content, '
        "created_at) VALUES ('r-$id', '$id', 'markdown', 1, ?, $seconds)",
        [text],
      );
      // Un chunk por párrafo, como los deja el fragmentador: juntos
      // reconstruyen el texto.
      final paragraphs = RegExp(
        r'[\s\S]*?(?:\n\n|$)',
      ).allMatches(text).toList();
      var seq = 0;
      for (final paragraph in paragraphs) {
        final content = paragraph[0]!;
        if (content.isEmpty) continue;
        await db.customStatement(
          'INSERT INTO chunks (id, item_id, seq, content, char_start, '
          "char_end) VALUES ('c-$id-$seq', '$id', $seq, ?, ?, ?)",
          [content, paragraph.start, paragraph.end],
        );
        seq++;
      }
    }
  }

  final tables = [
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
    ...VaultCounts.itemSpaceTables,
    ...VaultCounts.datedEventTables,
    ...VaultCounts.processedTables,
    ...VaultCounts.processedImageTables,
    ...VaultCounts.studyCreationTables,
    ...VaultCounts.textNoteTables,
    ...VaultCounts.processedHeadingTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in tables)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom51({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(51);
    final oldDb = v51.DatabaseAtV51(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<List<String>> itemsMatching(AppDatabase db, String input) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT DISTINCT c.item_id AS id FROM chunk_search '
              'JOIN chunks c ON c.row_key = chunk_search.rowid '
              'WHERE chunk_search MATCH ? ORDER BY c.item_id',
              variables: [Variable.withString(buildSearchQuery(input))],
            )
            .get())
      row.read<String>('id'),
  ];

  test('la migración llega a la forma del snapshot de v52', () async {
    await migrateFrom51();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(52));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(52));
  });

  Future<void> integrityCheck(AppDatabase db) => db.customStatement(
    "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
  );

  test('la migración solo agrega las columnas, vacías: la búsqueda anda como '
      'antes hasta que pase el relleno', () async {
    final db = await migrateFrom51();

    final chunks = await db.select(db.chunks).get();
    expect(chunks.every((c) => c.searchText == null), isTrue);
    expect(chunks.every((c) => c.searchTextRule == null), isTrue);
    expect(await itemsMatching(db, 'wikipedia'), ['web']);
    expect(await itemsMatching(db, 'fotosintesis'), ['web']);
    await integrityCheck(db);
  });

  test('el relleno guarda lo que se lee de cada chunk en Markdown, y el de un '
      'PDF solo recibe la versión', () async {
    final db = await migrateFrom51();

    expect(await ChunkSearchTextBackfill(database: db).run(), 5);

    final chunks = await (db.select(
      db.chunks,
    )..orderBy([(c) => OrderingTerm(expression: c.rowKey)])).get();
    final byItem = <String, List<ChunkRow>>{};
    for (final chunk in chunks) {
      (byItem[chunk.itemId] ??= []).add(chunk);
    }
    expect(byItem['web']!.map((c) => c.searchText), [
      // Se lee igual que como está guardado, salvo por los espacios.
      null,
      '',
      'Sube debido a la fotosíntesis de las ex-\nplicaciones.',
    ]);
    expect(byItem['word']!.single.searchText, 'Una cita.');
    expect(byItem['libro']!.single.searchText, isNull);
    expect(chunks.map((c) => c.searchTextRule).toSet(), {kChunkSearchTextRule});
    // Lo hecho no se rehace.
    expect(await ChunkSearchTextBackfill(database: db).run(), 0);
  });

  test('después del relleno el índice busca lo que se lee: las direcciones no '
      'se encuentran, los guiones de corte sí', () async {
    final db = await migrateFrom51();
    await ChunkSearchTextBackfill(database: db).run();

    expect(await itemsMatching(db, 'fotosintesis'), ['web']);
    expect(await itemsMatching(db, 'wikimedia'), ['libro']);
    expect(await itemsMatching(db, 'wikipedia'), isEmpty);
    expect(await itemsMatching(db, 'explicaciones'), ['web']);
    expect(await itemsMatching(db, 'cita'), ['word']);
    expect(await itemsMatching(db, 'x.org'), isEmpty);
    // Cada chunk cambió en el índice por su trigger, exacto.
    await integrityCheck(db);
    expect(
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM chunk_search_docsize')
              .getSingle())
          .read<int>('n'),
      (await db.select(db.chunks).get()).length,
    );
  });

  test('los triggers quedan puestos y siguen lo que se lee', () async {
    final db = await migrateFrom51();
    await ChunkSearchTextBackfill(database: db).run();
    final triggers = {
      for (final row
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'trigger'",
              )
              .get())
        row.read<String>('name'),
    };
    expect(triggers, containsAll(chunkSearchTriggerNames));

    await db.customStatement(
      "UPDATE chunks SET search_text = 'Clorofila.' WHERE id = 'c-web-2'",
    );
    expect(await itemsMatching(db, 'clorofila'), ['web']);
    expect(await itemsMatching(db, 'fotosintesis'), isEmpty);
    await db.customStatement("DELETE FROM chunks WHERE item_id = 'web'");
    expect(await itemsMatching(db, 'clorofila'), isEmpty);
    await db.customStatement(
      "INSERT INTO chunk_search (chunk_search) VALUES ('integrity-check')",
    );
  });

  test('el texto de la Biblioteca no se toca, y los conteos de todo son los '
      'mismos', () async {
    final before = <String, int>{};
    final db = await migrateFrom51(countsBefore: before);

    expect(await countsOf(db), before);
    final rendition = await (db.select(
      db.renditions,
    )..where((r) => r.itemId.equals('web'))).getSingle();
    expect(rendition.content, page);
    final web =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals('web'))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
            .get();
    expect(web.map((c) => c.content).join(), page);
  });
}
