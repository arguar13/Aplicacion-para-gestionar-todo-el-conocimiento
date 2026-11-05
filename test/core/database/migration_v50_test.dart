import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v49.dart' as v49;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 49→50: la nota sobre el texto entero (F45, paso
/// 8b) —sin lugar y sin pedazo—. Cambia una restricción de `text_notes`, y
/// SQLite solo lo hace rehaciendo la tabla: todo lo demás, y cada nota con su
/// `row_key`, tiene que quedar igual, y el índice de texto, al día.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v49.DatabaseAtV49 db) async {
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('fuente', 'Éxodo', 'source', 'triaged', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'fuente', 'plainText', "
      "'Moisés sube al monte y baja con las tablas.', 1, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO highlights (id, rendition_id, start_offset, end_offset, '
      'excerpt, note, created_at, color, style) VALUES '
      "('resaltado', 'texto', 0, 6, 'Moisés', 'Acá empieza la ley', "
      "$seconds, 'lime', 'fill')",
    );
    // Dos notas: una en su lugar y una que ya no lo tiene. La primera nace
    // con un `row_key` alto, que la tabla rehecha tiene que conservar: es el
    // del índice de texto.
    for (final (key, id, start, end, note) in [
      (40, 'con-lugar', '0', '6', 'El monte Sinaí'),
      (41, 'sin-lugar', 'NULL', 'NULL', 'Las tablas de piedra'),
    ]) {
      await db.customStatement(
        'INSERT INTO text_notes (row_key, id, target, item_id, rendition_id, '
        'start_offset, end_offset, excerpt, note, color, created_at, '
        "updated_at) VALUES ($key, '$id', 'source_original', 'fuente', "
        "'texto', $start, $end, 'Moisés', '$note', 'coral', $seconds, "
        '$seconds)',
      );
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in tables)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom49({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(49);
    final oldDb = v49.DatabaseAtV49(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  /// Lo que el índice de texto encuentra con [query]: `origin:note_id`.
  Future<Set<String>> found(AppDatabase db, String query) async => {
    for (final row
        in await db
            .customSelect(
              'SELECT origin, note_id FROM text_note_search '
              'WHERE text_note_search MATCH ?',
              variables: [Variable.withString(query)],
            )
            .get())
      '${row.read<String>('origin')}:${row.read<String>('note_id')}',
  };

  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  TextNotesCompanion whole(String id, {String excerpt = ''}) =>
      TextNotesCompanion.insert(
        id: id,
        target: 'source_original',
        itemId: const Value('fuente'),
        renditionId: const Value('texto'),
        excerpt: excerpt,
        note: 'Todo el Éxodo',
        color: HighlightColor.lime,
        createdAt: at,
        updatedAt: at,
      );

  test('la migración llega a la forma del snapshot de v50', () async {
    await migrateFrom49();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(50));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(50));
  });

  test('cada nota sigue igual, con su row_key, y el índice de texto las '
      'encuentra —también la del resaltado de antes—', () async {
    final db = await migrateFrom49();

    final notes = {
      for (final n in await db.select(db.textNotes).get()) n.id: n,
    };
    expect(notes.keys, {'con-lugar', 'sin-lugar'});
    expect(notes['con-lugar']!.rowKey, 40);
    expect(notes['con-lugar']!.startOffset, 0);
    expect(notes['con-lugar']!.color, HighlightColor.coral);
    expect(notes['sin-lugar']!.rowKey, 41);
    expect(notes['sin-lugar']!.startOffset, isNull);
    expect(await found(db, 'sinai'), {'note:con-lugar'});
    expect(await found(db, 'piedra'), {'note:sin-lugar'});
    expect(await found(db, 'ley'), {'highlight:resaltado'});
  });

  test('la nota sobre el texto entero entra: sin lugar y sin pedazo; con '
      'lugar, el pedazo sigue siendo obligatorio', () async {
    final db = await migrateFrom49();

    await db.into(db.textNotes).insert(whole('todo'));
    expect(await found(db, 'exodo'), {'note:todo'});
    await expectLater(
      db
          .into(db.textNotes)
          .insert(
            whole(
              'con-lugar-sin-pedazo',
            ).copyWith(startOffset: const Value(0), endOffset: const Value(6)),
          ),
      throwsA(anything),
    );
    // Y el índice sigue al día al borrar.
    await (db.delete(db.textNotes)..where((n) => n.id.equals('todo'))).go();
    expect(await found(db, 'exodo'), isEmpty);
  });

  test('nada más cambia: los conteos de todo, también de las notas, son los '
      'mismos', () async {
    final before = <String, int>{};
    final db = await migrateFrom49(countsBefore: before);

    expect(await countsOf(db), before);
  });
}
