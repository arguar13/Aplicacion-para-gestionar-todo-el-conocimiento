import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/processed_heading_triggers.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v50.dart' as v50;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 50→51: el Índice (F46, paso 2) —
/// `processed_headings`, su índice de texto y sus triggers— y el título de
/// cada imagen (`processed_images.title`). Solo agrega: la tabla nace vacía,
/// las imágenes quedan sin titular para el relleno y nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v50.DatabaseAtV50 db) async {
    for (final (id, kind) in [('fuente', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Roma', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'processed', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO processed_documents (item_id, source_item_id, source_kind, '
      "created_at) VALUES ('proc', 'fuente', 'webPage', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO processed_parts (id, document_id, section, position, '
      'content, origin, edited, source_start, source_end, text_start, '
      "text_end, created_at, updated_at) VALUES ('pagina', 'proc', 'text', "
      "0, '# Roma', 'copied', 0, 0, 6, 0, 6, $seconds, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, relative_path, is_primary, '
      "title, created_at) VALUES ('foto', 'proc', 'image', "
      "'originales/proc/imagenes/mapa.jpg', 0, 'Mapa de Roma', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO processed_images (rendition_id, document_id, position, '
      'source_file_path, source_file_size, copied_at) VALUES '
      "('foto', 'proc', 0, 'contenido/mapa.jpg', 10, $seconds)",
    );
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in tables)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom50({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(50);
    final oldDb = v50.DatabaseAtV50(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<Set<String>> namesOf(AppDatabase db, String type) async => {
    for (final row
        in await db
            .customSelect(
              'SELECT name FROM sqlite_master WHERE type = ?',
              variables: [Variable.withString(type)],
            )
            .get())
      row.read<String>('name'),
  };

  Future<List<String>> found(AppDatabase db, String query) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT h.title FROM processed_heading_search s '
              'JOIN processed_headings h ON h.row_key = s.rowid '
              'WHERE processed_heading_search MATCH ?',
              variables: [Variable.withString(query)],
            )
            .get())
      row.read<String>('title'),
  ];

  test('la migración llega a la forma del snapshot de v51', () async {
    await migrateFrom50();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(51));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(51));
  });

  test('la tabla nace vacía, con sus índices, su índice de texto y sus '
      'triggers', () async {
    final db = await migrateFrom50();

    expect(await db.select(db.processedHeadings).get(), isEmpty);
    expect(
      await namesOf(db, 'index'),
      containsAll(<String>[
        'idx_processed_headings_document',
        'idx_processed_images_untitled',
      ]),
    );
    expect(await namesOf(db, 'table'), contains('processed_heading_search'));
    expect(
      await namesOf(db, 'trigger'),
      containsAll(<String>[
        ...processedHeadingSearchTriggerNames,
        ...processedHeadingStaleTriggerNames,
        ...processedImageHeadingTriggerNames,
      ]),
    );
  });

  test('las imágenes que ya estaban quedan sin titular, para el relleno; '
      'titularlas les da su entrada, que se encuentra', () async {
    final db = await migrateFrom50();

    final image = await db.select(db.processedImages).getSingle();
    expect(image.title, isNull);
    expect(await db.select(db.processedHeadings).get(), isEmpty);

    await db.customStatement(
      "UPDATE processed_images SET title = 'Mapa de Roma' "
      "WHERE rendition_id = 'foto'",
    );
    final entry = await db.select(db.processedHeadings).getSingle();
    expect(entry.origin, IndexEntryOrigin.image);
    expect(entry.imageId, 'foto');
    expect(await found(db, 'mapa'), ['Mapa de Roma']);
  });

  test('el texto que ya estaba queda sin indexar: tiene texto y ninguna '
      'entrada de texto', () async {
    final db = await migrateFrom50();

    final row = await db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM processed_parts '
          "WHERE document_id = 'proc' AND section = 'text') AS has_text, "
          'EXISTS (SELECT 1 FROM processed_headings '
          "WHERE document_id = 'proc' AND origin <> 'image') AS indexed",
        )
        .getSingle();
    expect(row.read<bool>('has_text'), isTrue);
    expect(row.read<bool>('indexed'), isFalse);
  });

  test('nada más cambia: los conteos de todo son los mismos', () async {
    final before = <String, int>{};
    final db = await migrateFrom50(countsBefore: before);

    expect(await countsOf(db), before);
  });
}
