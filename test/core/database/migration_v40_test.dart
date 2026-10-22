import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v39.dart' as v39;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 39→40: resumen, síntesis y palabras clave
/// resaltados en el documento (F36, decisión 79). Dos tablas nuevas y vacías
/// —`study_marks` y `study_analyses`— y una columna en la papelera del
/// contenido —`content_trash.study_marks`— que en todo lo de antes dice
/// «nada». Nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v39.DatabaseAtV39 db) async {
    // El esquema v39 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('libro', 'Un libro', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO source (item_id, source_type, captured_at, '
      'original_blob_path, content_hash, processing_status) VALUES '
      "('libro', 'document', $seconds, 'originales/libro.pdf', '', 'done')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('libro-texto', 'libro', 'plainText', "
      "'Primera oración. Segunda oración.', 1, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO highlights (id, rendition_id, start_offset, end_offset, '
      "excerpt, created_at) VALUES ('marca', 'libro-texto', 0, 7, 'Primera', "
      '$seconds)',
    );
    await db.customStatement(
      'INSERT INTO content_trash (id, item_id, kind, rendition_id, '
      'rendition_kind, content, is_primary, rendition_created_at, '
      "trashed_at) VALUES ('suelto', 'libro', 'text', 'viejo', 'plainText', "
      "'Un texto soltado.', 0, $seconds, $seconds)",
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom39({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(39);
    final oldDb = v39.DatabaseAtV39(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  StudyMarksCompanion mark(String id, {int start = 0, int end = 16}) =>
      StudyMarksCompanion.insert(
        id: id,
        renditionId: 'libro-texto',
        kind: StudyMarkKind.summary,
        origin: ContentOrigin.ai,
        startOffset: start,
        endOffset: end,
        excerpt: 'Primera oración.',
        createdAt: at,
      );

  test('la migración llega a la forma del snapshot de v40', () async {
    await migrateFrom39();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(40));
  });

  test('nada se analizó todavía: sin marcas, sin análisis, y lo de la '
      'papelera sin marcas de estudio', () async {
    final db = await migrateFrom39();

    expect(await db.select(db.studyMarks).get(), isEmpty);
    expect(await db.select(db.studyAnalyses).get(), isEmpty);
    final trashed = await db.select(db.trashedContents).getSingle();
    expect(trashed.studyMarks, isNull);
    expect(trashed.content, 'Un texto soltado.');
  });

  test(
    'una marca exige un rango que tenga sentido y se va con su forma',
    () async {
      final db = await migrateFrom39();

      await db.into(db.studyMarks).insert(mark('bien'));
      await expectLater(
        db.into(db.studyMarks).insert(mark('vacía', start: 5, end: 5)),
        throwsA(isA<Object>()),
      );
      await expectLater(
        db.into(db.studyMarks).insert(mark('negativa', start: -1, end: 3)),
        throwsA(isA<Object>()),
      );
      await db
          .into(db.studyAnalyses)
          .insert(
            StudyAnalysesCompanion.insert(
              renditionId: 'libro-texto',
              analyzedUntil: 16,
              updatedAt: at,
            ),
          );

      await db.customStatement(
        "DELETE FROM renditions WHERE id = 'libro-texto'",
      );
      expect(await db.select(db.studyMarks).get(), isEmpty);
      expect(await db.select(db.studyAnalyses).get(), isEmpty);
    },
  );

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom39(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
