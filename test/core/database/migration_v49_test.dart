import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v48.dart' as v48;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 48→49: las notas en el texto (F45, mejora 19,
/// decisión I) —la tabla `text_notes`, sus índices y su índice de texto, que
/// lleva también las notas de los resaltados de antes sin migrarlos—. Solo
/// agrega.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v48.DatabaseAtV48 db) async {
    for (final (id, kind) in [('fuente', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Éxodo', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'processed', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO processed_documents (item_id, source_item_id, source_kind, '
      "created_at) VALUES ('proc', 'fuente', 'book', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'fuente', 'plainText', "
      "'Moisés sube al monte y baja con las tablas.', 1, $seconds)",
    );
    // Tres resaltados de antes: uno con nota, uno sin nota y uno con la
    // nota en blanco. Solo el primero es una nota.
    for (final (id, note) in [
      ('con-nota', "'Acá empieza la ley'"),
      ('sin-nota', 'NULL'),
      ('en-blanco', "'   '"),
    ]) {
      await db.customStatement(
        'INSERT INTO highlights (id, rendition_id, start_offset, end_offset, '
        'excerpt, note, created_at, color, style) VALUES '
        "('$id', 'texto', 0, 6, 'Moisés', $note, $seconds, 'lime', 'fill')",
      );
    }
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
    ...VaultCounts.itemSpaceTables,
    ...VaultCounts.datedEventTables,
    ...VaultCounts.processedTables,
    ...VaultCounts.processedImageTables,
    ...VaultCounts.studyCreationTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom48({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(48);
    final oldDb = v48.DatabaseAtV48(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  TextNotesCompanion note(
    String id, {
    String target = 'source_original',
    String? itemId = 'fuente',
    String? renditionId = 'texto',
    String? creationId,
    String text = 'Por qué sube',
  }) => TextNotesCompanion.insert(
    id: id,
    target: target,
    itemId: Value(itemId),
    renditionId: Value(renditionId),
    creationId: Value(creationId),
    startOffset: const Value(0),
    endOffset: const Value(6),
    excerpt: 'Moisés',
    note: text,
    color: HighlightColor.lime,
    createdAt: at,
    updatedAt: at,
  );

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

  test('la migración llega a la forma del snapshot de v49', () async {
    await migrateFrom48();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(49));
  });

  test('la tabla nace vacía, con sus tres índices', () async {
    final db = await migrateFrom48();

    expect(await db.select(db.textNotes).get(), isEmpty);
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'text_notes' AND name LIKE 'idx_%' ORDER BY name",
        )
        .get();
    expect(
      [for (final row in indexes) row.read<String>('name')],
      [
        'idx_text_notes_creation',
        'idx_text_notes_item',
        'idx_text_notes_rendition',
      ],
    );
  });

  test(
    'los resaltados de antes con nota quedan en el índice de texto, sin '
    'migrarlos ni tocarlos: el de la nota en blanco y el sin nota, no',
    () async {
      final db = await migrateFrom48();

      expect(await found(db, 'ley'), {'highlight:con-nota'});
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM text_note_search')
                .getSingle())
            .read<int>('n'),
        1,
      );
      // Los resaltados siguen como estaban, y nada pasó a `text_notes`.
      final highlights = await db.select(db.highlights).get();
      expect(highlights, hasLength(3));
      expect(
        highlights.firstWhere((h) => h.id == 'con-nota').note,
        'Acá empieza la ley',
      );
      expect(await db.select(db.textNotes).get(), isEmpty);
    },
  );

  test('el índice de texto sigue al día después: notas nuevas, editadas y '
      'borradas, y la nota de un resaltado que se pone o se saca', () async {
    final db = await migrateFrom48();

    await db.into(db.textNotes).insert(note('n1', text: 'Las tablas'));
    expect(await found(db, 'tablas'), {'note:n1'});

    await (db.update(db.textNotes)..where((n) => n.id.equals('n1'))).write(
      const TextNotesCompanion(note: Value('El monte Sinaí')),
    );
    expect(await found(db, 'tablas'), isEmpty);
    expect(await found(db, 'sinai'), {'note:n1'});

    await (db.update(db.highlights)..where((h) => h.id.equals('sin-nota')))
        .write(const HighlightsCompanion(note: Value('Otra ley')));
    expect(await found(db, 'ley'), {
      'highlight:con-nota',
      'highlight:sin-nota',
    });
    await (db.update(db.highlights)..where((h) => h.id.equals('con-nota')))
        .write(const HighlightsCompanion(note: Value(null)));
    expect(await found(db, 'ley'), {'highlight:sin-nota'});

    await (db.delete(db.textNotes)..where((n) => n.id.equals('n1'))).go();
    expect(await found(db, 'sinai'), isEmpty);
  });

  test('cada clase con su dueño, y la base lo hace cumplir', () async {
    final db = await migrateFrom48();

    await db.into(db.textNotes).insert(note('fuente'));
    await db
        .into(db.textNotes)
        .insert(
          note(
            'copia',
            target: 'processed_original',
            itemId: 'proc',
            renditionId: null,
          ),
        );
    expect(await db.select(db.textNotes).get(), hasLength(2));

    Future<void> rejects(TextNotesCompanion row) =>
        expectLater(db.into(db.textNotes).insert(row), throwsA(anything));

    // Una clase que no existe.
    await rejects(note('rara', target: 'otra'));
    // El original de la Biblioteca, sin su forma; la copia, con una.
    await rejects(note('sin-forma', renditionId: null));
    await rejects(note('con-forma', target: 'processed_text', itemId: 'proc'));
    // Una creación con elemento, o un texto sin él.
    await rejects(
      note('mezcla', target: 'creation', renditionId: null, creationId: 'c'),
    );
    await rejects(note('suelta', itemId: null));
    // En blanco, o con el lugar a medias.
    await rejects(note('blanca', text: '  '));
    await rejects(note('media').copyWith(endOffset: const Value(null)));
    // Sin lugar sí: es la que ya no se encontró.
    await db
        .into(db.textNotes)
        .insert(
          note('sin-lugar').copyWith(
            startOffset: const Value(null),
            endOffset: const Value(null),
          ),
        );
  });

  test('se va con su elemento, pero no con su forma de texto: sin el texto '
      'queda sin lugar, nunca se pierde', () async {
    final db = await migrateFrom48();
    await db.into(db.textNotes).insert(note('n1'));
    await db
        .into(db.textNotes)
        .insert(
          note(
            'n2',
            target: 'processed_text',
            itemId: 'proc',
            renditionId: null,
          ),
        );

    await db.customStatement("DELETE FROM renditions WHERE id = 'texto'");
    expect(
      {for (final n in await db.select(db.textNotes).get()) n.id},
      {'n1', 'n2'},
    );

    await db.customStatement("DELETE FROM item WHERE id = 'fuente'");
    expect({for (final n in await db.select(db.textNotes).get()) n.id}, {'n2'});
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom48(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
