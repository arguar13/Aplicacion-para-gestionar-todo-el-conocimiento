import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v37.dart' as v37;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 37→38: la Bandeja de texto (F30, decisión 68). Una
/// tabla nueva y vacía —la papelera del contenido, `content_trash`— y una
/// columna en la fuente —«solo el libro», `source.only_file`— que en todo lo
/// de antes dice «no». Nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v37.DatabaseAtV37 db) async {
    // El esquema v37 generado no trae clases de datos: SQL directo.
    for (final (id, kind) in [('libro', 'document'), ('clase', 'audio')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Un $kind', 'source', 'processed', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
      await db.customStatement(
        'INSERT INTO source (item_id, source_type, captured_at, '
        'original_blob_path, content_hash, processing_status) VALUES '
        "('$id', '$kind', $seconds, 'originales/$id/$id.bin', '', 'done')",
      );
      await db.customStatement(
        'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
        "created_at) VALUES ('$id-texto', '$id', 'plainText', "
        "'El texto de $id.', 1, $seconds)",
      );
    }
    await db.customStatement(
      'INSERT INTO highlights (id, rendition_id, start_offset, end_offset, '
      "excerpt, created_at) VALUES ('marca', 'libro-texto', 0, 5, 'El te', "
      '$seconds)',
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom37({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(37);
    final oldDb = v37.DatabaseAtV37(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v38', () async {
    await migrateFrom37();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(38));
  });

  test('nada se soltó todavía: ninguna fuente es «solo el libro» y la '
      'papelera del contenido está vacía', () async {
    final db = await migrateFrom37();

    final sources = await db.select(db.knowledgeSources).get();
    expect(sources, hasLength(2));
    expect(sources.map((s) => s.onlyFile), everyElement(isFalse));
    // Lo de antes queda donde estaba: el archivo y el texto, a la vista.
    expect(
      sources.map((s) => s.originalBlobPath),
      containsAll(['originales/libro/libro.bin', 'originales/clase/clase.bin']),
    );
    expect(await db.select(db.trashedContents).get(), isEmpty);
  });

  test('la papelera del contenido nueva exige lo suyo: un archivo con su '
      'ruta y un texto con su forma', () async {
    final db = await migrateFrom37();
    final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.trashedContents)
        .insert(
          TrashedContentsCompanion.insert(
            id: 'archivo',
            itemId: 'libro',
            kind: TrashedContentKind.file,
            relativePath: const Value('originales/libro/libro.bin'),
            trashedAt: at,
          ),
        );
    // Un archivo sin ruta no significa nada.
    await expectLater(
      db
          .into(db.trashedContents)
          .insert(
            TrashedContentsCompanion.insert(
              id: 'sin-ruta',
              itemId: 'libro',
              kind: TrashedContentKind.file,
              trashedAt: at,
            ),
          ),
      throwsA(isA<Object>()),
    );
    // Un texto sin su forma no se podría recuperar.
    await expectLater(
      db
          .into(db.trashedContents)
          .insert(
            TrashedContentsCompanion.insert(
              id: 'texto-suelto',
              itemId: 'libro',
              kind: TrashedContentKind.text,
              content: const Value('Un texto'),
              trashedAt: at,
            ),
          ),
      throwsA(isA<Object>()),
    );
    // Y se va con su elemento.
    await db.customStatement("DELETE FROM item WHERE id = 'libro'");
    expect(await db.select(db.trashedContents).get(), isEmpty);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom37(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
