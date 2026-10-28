import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v46.dart' as v46;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 46→47: las imágenes en Procesado (F41, decisión
/// L) —`processed_images` y `content_trash.processed_image`—. Solo agrega.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000;

  Future<void> seedVault(v46.DatabaseAtV46 db) async {
    for (final (id, kind) in [('foto', 'source'), ('proc', 'note')]) {
      await db.customStatement(
        'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
        "device_id) VALUES ('$id', 'Una foto', '$kind', 'triaged', "
        "$seconds, $seconds, 'dispositivo-a')",
      );
    }
    await db.customStatement(
      "INSERT INTO note (item_id, note_kind, maturity) VALUES ('proc', "
      "'processed', 'seed')",
    );
    await db.customStatement(
      'INSERT INTO processed_documents (item_id, source_item_id, source_kind, '
      "created_at) VALUES ('proc', 'foto', 'image', $seconds)",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, relative_path, is_primary, '
      "created_at) VALUES ('copia', 'proc', 'image', "
      "'originales/proc/imagenes/foto.jpg', 0, $seconds)",
    );
    await db.customStatement(
      'INSERT INTO content_trash (id, item_id, kind, relative_path, '
      "trashed_at) VALUES ('soltado', 'foto', 'file', "
      "'originales/foto/foto.jpg', $seconds)",
    );
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
    ...VaultCounts.processedTables,
  ];

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in untouched)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom46({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(46);
    final oldDb = v46.DatabaseAtV46(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v47', () async {
    await migrateFrom46();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(47));
  });

  test('lo nuevo nace vacío: sin imágenes, y lo soltado sigue siendo lo '
      'que era', () async {
    final db = await migrateFrom46();

    expect(await db.select(db.processedImages).get(), isEmpty);
    final trashed = await db.select(db.trashedContents).getSingle();
    expect(trashed.processedImage, isNull);
    expect(trashed.relativePath, 'originales/foto/foto.jpg');
  });

  test('una imagen cuelga de su forma y de su documento, y la misma imagen '
      'de la fuente no entra dos veces', () async {
    final db = await migrateFrom46();
    final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    ProcessedImagesCompanion image(String rendition) =>
        ProcessedImagesCompanion.insert(
          renditionId: rendition,
          documentId: 'proc',
          position: 0,
          sourceFilePath: 'originales/foto/foto.jpg',
          sourceFileSize: 10,
          copiedAt: at,
        );

    await db.into(db.processedImages).insert(image('copia'));
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'otra',
            itemId: 'proc',
            kind: RenditionKind.image,
            relativePath: const Value('originales/proc/imagenes/otra.jpg'),
            isPrimary: false,
            createdAt: at,
          ),
        );
    await expectLater(
      db.into(db.processedImages).insert(image('otra')),
      throwsA(anything),
    );
    await expectLater(
      db
          .into(db.processedImages)
          .insert(
            image('otra').copyWith(
              position: const Value(-1),
              sourceFilePath: const Value('originales/foto/otra.jpg'),
            ),
          ),
      throwsA(anything),
    );

    // Sin su forma no hay imagen.
    await (db.delete(db.renditions)..where((r) => r.id.equals('copia'))).go();
    expect(await db.select(db.processedImages).get(), isEmpty);
  });

  test(
    'nada más cambia: los conteos de todo lo demás son los mismos',
    () async {
      final before = <String, int>{};
      final db = await migrateFrom46(countsBefore: before);

      expect(await countsOf(db), before);
    },
  );
}
