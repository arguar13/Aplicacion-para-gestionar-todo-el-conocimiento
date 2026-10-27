import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v44.dart' as v44;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 44→45: los documentos procesados (F41, paso 1). Dos
/// tablas nuevas y vacías (`processed_documents`, `processed_parts`), el
/// índice de texto de las partes y una columna que en todo lo de antes dice
/// «ninguna»: `content_trash.processed_parts`. No se procesa nada solo
/// (decisión D) ni se toca ninguna fuente.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.
  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  Future<void> seedVault(v44.DatabaseAtV44 db) async {
    // El esquema v44 generado no trae clases de datos: SQL directo.
    for (final (id, kind) in [('libro', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Un libro', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'living', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'libro', 'plainText', 'Texto.', 1, "
      '$seconds)',
    );
    await db.customStatement(
      'INSERT INTO content_trash (id, item_id, kind, rendition_id, '
      'rendition_kind, content, is_primary, rendition_created_at, '
      "trashed_at) VALUES ('papelera', 'libro', 'text', 'viejo', "
      "'plainText', 'Otro texto.', 0, $seconds, $seconds)",
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
    ...VaultCounts.itemSpaceTables,
    ...VaultCounts.datedEventTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom44({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(44);
    final oldDb = v44.DatabaseAtV44(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  ProcessedPartsCompanion part(String id, String content) =>
      ProcessedPartsCompanion.insert(
        id: id,
        documentId: 'proc',
        section: ProcessedSection.text,
        position: 0,
        content: content,
        origin: ProcessedPartOrigin.copied,
        sourceRenditionId: const Value('texto'),
        sourceStart: const Value(0),
        sourceEnd: const Value(6),
        createdAt: at,
        updatedAt: at,
      );

  Future<List<String>> search(AppDatabase db, String term) async => [
    for (final row
        in await db
            .customSelect(
              'SELECT pp.id AS id FROM processed_part_search '
              'JOIN processed_parts pp '
              'ON pp.row_key = processed_part_search.rowid '
              'WHERE processed_part_search MATCH ?',
              variables: [Variable.withString(term)],
            )
            .get())
      row.read<String>('id'),
  ];

  test('la migración llega a la forma del snapshot de v45', () async {
    await migrateFrom44();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(45));
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(45));
  });

  test('nace vacía: ningún procesado, y lo de antes sigue', () async {
    final db = await migrateFrom44();

    expect(await db.select(db.processedDocuments).get(), isEmpty);
    expect(await db.select(db.processedParts).get(), isEmpty);
    final trashed = await db.select(db.trashedContents).getSingle();
    expect(trashed.processedParts, isNull);
    expect(trashed.content, 'Otro texto.');
  });

  test('un procesado se guarda, se busca por sus partes y se va con su '
      'elemento; su fuente, si se va, solo lo deja sin enlace', () async {
    final db = await migrateFrom44();
    await db
        .into(db.processedDocuments)
        .insert(
          ProcessedDocumentsCompanion.insert(
            itemId: 'proc',
            sourceItemId: const Value('libro'),
            sourceKind: SourceKind.document,
            createdAt: at,
          ),
        );
    await db.into(db.processedParts).insert(part('p1', 'Acueductos romanos'));

    expect(await search(db, 'acueducto*'), ['p1']);
    await (db.update(db.processedParts)..where((p) => p.id.equals('p1'))).write(
      const ProcessedPartsCompanion(content: Value('Termas')),
    );
    expect(await search(db, 'acueducto*'), isEmpty);
    expect(await search(db, 'termas'), ['p1']);

    await (db.delete(db.renditions)..where((r) => r.id.equals('texto'))).go();
    final loose = await db.select(db.processedParts).getSingle();
    expect(loose.sourceRenditionId, isNull);
    expect((loose.sourceStart, loose.sourceEnd), (0, 6));

    await (db.delete(
      db.knowledgeEntries,
    )..where((e) => e.id.equals('libro'))).go();
    expect(
      (await db.select(db.processedDocuments).getSingle()).sourceItemId,
      isNull,
    );

    await (db.delete(
      db.knowledgeEntries,
    )..where((e) => e.id.equals('proc'))).go();
    expect(await db.select(db.processedDocuments).get(), isEmpty);
    expect(await db.select(db.processedParts).get(), isEmpty);
    expect(await search(db, 'termas'), isEmpty);
    // Y el índice quedó como su tabla: sin entradas de lo que ya no está.
    final indexed = await db
        .customSelect('SELECT COUNT(*) AS n FROM processed_part_search_docsize')
        .getSingle();
    expect(indexed.read<int>('n'), 0);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom44(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );

  test(
    'una base nueva también trae el índice de texto de las partes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name LIKE 'processed_part%'",
          )
          .get();
      expect(
        tables.map((r) => r.read<String>('name')),
        containsAll([
          'processed_parts',
          'processed_part_search',
          'processed_part_search_text',
          'processed_parts_search_ai',
          'processed_parts_search_ad',
          'processed_parts_search_au',
        ]),
      );
    },
  );
}
