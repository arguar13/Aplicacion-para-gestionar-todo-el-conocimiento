import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v45.dart' as v45;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 45→46: el ajuste del dueño a F41 (palabras clave,
/// la copia del original, estudiar el procesado en él mismo) y el vaciado de
/// los cuadernos del paso 5.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v45.DatabaseAtV45 db) async {
    for (final (id, kind) in [('libro', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Un libro', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'processed', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'libro', 'plainText', "
      "'Acueductos romanos.', 1, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO processed_documents (item_id, source_item_id, source_kind, '
      "created_at) VALUES ('proc', 'libro', 'document', $seconds)",
    );
    for (final (id, section) in [('pagina', 'text'), ('oracion', 'summary')]) {
      await db.customStatement(
        'INSERT INTO processed_parts (id, document_id, section, position, '
        'content, origin, edited, source_rendition_id, source_start, '
        "source_end, created_at, updated_at) VALUES ('$id', 'proc', "
        "'$section', 0, 'Acueductos romanos.', 'copied', 0, 'texto', 0, 19, "
        '$seconds, $seconds)',
      );
    }
    // Los cuadernos: con una fuente y un procesado, solo con el procesado,
    // por consulta, y vacío.
    for (final (id, mode, query) in [
      ('mezclado', 'manual', 'NULL'),
      ('procesados', 'manual', 'NULL'),
      ('consulta', 'query', "'{}'"),
      ('vacio', 'manual', 'NULL'),
    ]) {
      await db.customStatement(
        'INSERT INTO notebook (id, name, mode, query_json, created_at, '
        "updated_at) VALUES ('$id', '$id', '$mode', $query, $seconds, "
        '$seconds)',
      );
    }
    for (final (notebook, item) in [
      ('mezclado', 'libro'),
      ('mezclado', 'proc'),
      ('procesados', 'proc'),
    ]) {
      await db.customStatement(
        "INSERT INTO notebook_item (notebook_id, item_id) VALUES ('$notebook', "
        "'$item')",
      );
    }
  }

  final untouched = [
    ...VaultCounts.userDataTables,
    ...VaultCounts.modelTables,
    ...VaultCounts.durabilityTables,
    ...VaultCounts.referenceTables,
    ...VaultCounts.viewsAndTemplatesTables,
    ...VaultCounts.habitTables,
    ...VaultCounts.quizTables,
    ...VaultCounts.aiTables,
    ...VaultCounts.aiFieldChangeTables,
    ...VaultCounts.contentTrashTables,
    ...VaultCounts.studyTables,
    ...VaultCounts.itemSpaceTables,
    ...VaultCounts.datedEventTables,
    'processed_documents',
    'processed_parts',
    'notebook',
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom45({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(45);
    final oldDb = v45.DatabaseAtV45(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v46', () async {
    await migrateFrom45();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(46));
  });

  test(
    'las partes siguen, con su clave del índice, y el índice las encuentra',
    () async {
      final db = await migrateFrom45();

      final parts = await db.select(db.processedParts).get();
      expect(parts.map((p) => p.id), unorderedEquals(['pagina', 'oracion']));
      expect(
        parts.every((p) => p.textStart == null && p.spans == null),
        isTrue,
      );
      final hits = await db
          .customSelect(
            'SELECT pp.id AS id FROM processed_part_search '
            'JOIN processed_parts pp '
            'ON pp.row_key = processed_part_search.rowid '
            "WHERE processed_part_search MATCH 'acueducto*'",
          )
          .get();
      expect(hits, hasLength(2));
      // Y se sigue manteniendo solo.
      await (db.update(db.processedParts)..where((p) => p.id.equals('pagina')))
          .write(const ProcessedPartsCompanion(content: Value('Termas.')));
      final termas = await db
          .customSelect(
            'SELECT rowid FROM processed_part_search '
            "WHERE processed_part_search MATCH 'termas'",
          )
          .get();
      expect(termas, hasLength(1));
    },
  );

  test('lo nuevo nace vacío: sin copias del original, sin estudio', () async {
    final db = await migrateFrom45();

    expect(await db.select(db.processedOriginals).get(), isEmpty);
    final document = await db.select(db.processedDocuments).getSingle();
    expect(document.studyAnalyzedUntil, 0);
    expect(document.studyCompletedAt, isNull);
  });

  test('los cuadernos se vacían de lo que no es procesado, y los que tenían '
      'algo quedan marcados', () async {
    final db = await migrateFrom45();

    final items = await db.select(db.notebookItems).get();
    expect(
      items.map((i) => (i.notebookId, i.itemId)),
      unorderedEquals([('mezclado', 'proc'), ('procesados', 'proc')]),
    );
    final emptied = {
      for (final notebook in await db.select(db.notebooks).get())
        notebook.id: notebook.emptiedForProcessedAt != null,
    };
    expect(emptied, {
      'mezclado': true,
      'procesados': false,
      'consulta': true,
      'vacio': false,
    });
  });

  test('las palabras clave llevan sus tramos, y solo ellas', () async {
    final db = await migrateFrom45();
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    ProcessedPartsCompanion keyword({String? spans}) =>
        ProcessedPartsCompanion.insert(
          id: 'k-$spans',
          documentId: 'proc',
          section: ProcessedSection.keywords,
          position: 1,
          content: 'Acueductos romanos.',
          origin: ProcessedPartOrigin.copied,
          sourceStart: const Value(0),
          sourceEnd: const Value(19),
          spans: Value(spans),
          createdAt: now,
          updatedAt: now,
        );

    await db.into(db.processedParts).insert(keyword(spans: '[[0,10]]'));
    await expectLater(
      db.into(db.processedParts).insert(keyword()),
      throwsA(anything),
    );
    await expectLater(
      db
          .into(db.processedParts)
          .insert(
            keyword(spans: '[]').copyWith(
              id: const Value('resumen'),
              section: const Value(ProcessedSection.summary),
            ),
          ),
      throwsA(anything),
    );
    // Lo estudiado en el procesado es resumen, síntesis o palabras clave.
    await expectLater(
      db
          .into(db.processedParts)
          .insert(
            keyword().copyWith(
              id: const Value('nota'),
              section: const Value(ProcessedSection.notes),
              origin: const Value(ProcessedPartOrigin.studied),
            ),
          ),
      throwsA(anything),
    );
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom45(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
