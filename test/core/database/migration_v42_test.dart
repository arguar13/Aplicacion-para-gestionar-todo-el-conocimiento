import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v41.dart' as v41;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 41→42: el color y el estilo de cada subrayado
/// (F38). Dos columnas en `highlights` que en todo lo de antes dicen «el color
/// de siempre» y «fondo». Nada más cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v41.DatabaseAtV41 db) async {
    // El esquema v41 generado no trae clases de datos: SQL directo.
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
      "excerpt, note, created_at) VALUES ('marca', 'libro-texto', 0, 7, "
      "'Primera', 'Por qué importa', $seconds)",
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
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom41({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(41);
    final oldDb = v41.DatabaseAtV41(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v42', () async {
    await migrateFrom41();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(42));
  });

  test('un subrayado de antes queda con el color de siempre, de fondo, y con '
      'su tramo y su nota', () async {
    final db = await migrateFrom41();

    final row = await db.select(db.highlights).getSingle();
    expect(row.color, isNull);
    expect(row.style, HighlightStyle.fill);
    expect(row.excerpt, 'Primera');
    expect(row.note, 'Por qué importa');
    expect((row.startOffset, row.endOffset), (0, 7));
  });

  test('uno nuevo guarda su color y su estilo', () async {
    final db = await migrateFrom41();

    await db
        .into(db.highlights)
        .insert(
          HighlightsCompanion.insert(
            id: 'nuevo',
            renditionId: 'libro-texto',
            startOffset: 17,
            endOffset: 24,
            excerpt: 'Segunda',
            createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            color: const Value(HighlightColor.turquoise),
            style: const Value(HighlightStyle.underline),
          ),
        );

    final row = await (db.select(
      db.highlights,
    )..where((h) => h.id.equals('nuevo'))).getSingle();
    expect(row.color, HighlightColor.turquoise);
    expect(row.style, HighlightStyle.underline);
  });

  test(
    'los nueve colores van y vuelven por su nombre, y los guardados con '
    'los cuatro de antes siguen leyéndose igual (F39: sin migración)',
    () async {
      final db = await migrateFrom41();

      // Lo que dejó F38 en disco: el nombre del color, en texto.
      var offset = 100;
      for (final name in ['lightYellow', 'orange', 'violet', 'turquoise']) {
        await db.customStatement(
          'INSERT INTO highlights (id, rendition_id, start_offset, end_offset, '
          "excerpt, created_at, color) VALUES ('viejo-$name', 'libro-texto', "
          "$offset, ${offset + 3}, 'x', $seconds, '$name')",
        );
        offset += 10;
      }
      for (final color in HighlightColor.values) {
        await db
            .into(db.highlights)
            .insert(
              HighlightsCompanion.insert(
                id: 'nuevo-${color.name}',
                renditionId: 'libro-texto',
                startOffset: offset,
                endOffset: offset + 3,
                excerpt: 'x',
                createdAt: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
                color: Value(color),
              ),
            );
        offset += 10;
      }

      final rows = {
        for (final r in await db.select(db.highlights).get()) r.id: r,
      };
      expect(rows['viejo-lightYellow']!.color, HighlightColor.lightYellow);
      expect(rows['viejo-orange']!.color, HighlightColor.orange);
      expect(rows['viejo-violet']!.color, HighlightColor.violet);
      expect(rows['viejo-turquoise']!.color, HighlightColor.turquoise);
      for (final color in HighlightColor.values) {
        expect(rows['nuevo-${color.name}']!.color, color);
      }
      final stored = await db
          .customSelect(
            "SELECT color FROM highlights WHERE id LIKE 'nuevo-%' "
            'ORDER BY start_offset',
          )
          .get();
      expect(stored.map((r) => r.read<String>('color')), [
        for (final color in HighlightColor.values) color.name,
      ]);
    },
  );

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom41(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
