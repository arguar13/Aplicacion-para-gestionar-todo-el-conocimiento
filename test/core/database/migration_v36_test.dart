import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v35.dart' as v35;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 35→36 —bajar todo de páginas y publicaciones
/// (F30)—: las formas ganan título, dirección de origen, tipo, tamaño, orden
/// y de qué archivo es cada texto, y aparece la lista de trabajo de lo que
/// ofrece cada página. Aditiva: las formas de antes quedan con todo eso nulo,
/// y ninguna fila cambia.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1790000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedVault(v35.DatabaseAtV35 db) async {
    // El esquema v35 generado no trae clases de datos: SQL directo.
    await db.customStatement(
      'INSERT INTO item (id, title, kind, state, created_at, updated_at, '
      "device_id) VALUES ('una-pagina', 'Roma', 'source', 'processed', "
      "$seconds, $seconds, 'dispositivo-a')",
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, content, is_primary, '
      "created_at) VALUES ('texto', 'una-pagina', 'markdown', 'Roma fue…', "
      '1, $seconds)',
    );
    await db.customStatement(
      'INSERT INTO renditions (id, item_id, kind, relative_path, is_primary, '
      "created_at) VALUES ('pagina', 'una-pagina', 'html', "
      "'originales/s/Roma.html', 0, $seconds)",
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

  Future<AppDatabase> migrateFrom35({Map<String, int>? countsBefore}) async {
    final schema = await verifier.schemaAt(35);
    final oldDb = v35.DatabaseAtV35(schema.newConnection());
    await seedVault(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('la migración llega a la forma del snapshot de v36', () async {
    await migrateFrom35();
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(36));
  });

  test('no cambia ninguna fila de lo que había', () async {
    final before = <String, int>{};
    final db = await migrateFrom35(countsBefore: before);

    expect(await countsOf(db), before);
    expect(before['renditions'], 2);
  });

  test(
    'las formas de antes quedan iguales, sin nada del «Contenido»',
    () async {
      final db = await migrateFrom35();

      final rows = await db.select(db.renditions).get();
      expect(rows.map((r) => r.id), unorderedEquals(['texto', 'pagina']));
      for (final row in rows) {
        expect(row.title, isNull);
        expect(row.originUrl, isNull);
        expect(row.mimeType, isNull);
        expect(row.sizeBytes, isNull);
        expect(row.position, isNull);
        expect(row.textOf, isNull);
      }
      final page = rows.singleWhere((r) => r.id == 'pagina');
      expect(page.relativePath, 'originales/s/Roma.html');
    },
  );

  test('un archivo del «Contenido» con su texto, y la lista de trabajo; cada '
      'cosa se va con lo suyo', () async {
    final db = await migrateFrom35();
    await db.customStatement('PRAGMA foreign_keys = ON');
    final now = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'foto',
            itemId: 'una-pagina',
            kind: RenditionKind.image,
            isPrimary: false,
            createdAt: now,
            relativePath: const Value('originales/s/contenido/Coliseo.jpg'),
            title: const Value('El Coliseo'),
            originUrl: const Value('https://upload.wikimedia.org/c.jpg'),
            mimeType: const Value('image/jpeg'),
            sizeBytes: const Value(56378),
            position: const Value(0),
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'texto-foto',
            itemId: 'una-pagina',
            kind: RenditionKind.plainText,
            isPrimary: false,
            createdAt: now,
            content: const Value('COLOSSEVM'),
            textOf: const Value('foto'),
          ),
        );
    await db
        .into(db.attachmentDownloads)
        .insert(
          AttachmentDownloadsCompanion.insert(
            id: 'bajada',
            itemId: 'una-pagina',
            url: 'https://upload.wikimedia.org/c.jpg',
            kind: RenditionKind.image,
            position: 0,
            status: AttachmentDownloadStatus.done,
            renditionId: const Value('foto'),
            createdAt: now,
          ),
        );

    // La misma dirección dos veces en el mismo elemento, no.
    await expectLater(
      db
          .into(db.attachmentDownloads)
          .insert(
            AttachmentDownloadsCompanion.insert(
              id: 'otra',
              itemId: 'una-pagina',
              url: 'https://upload.wikimedia.org/c.jpg',
              kind: RenditionKind.image,
              position: 1,
              status: AttachmentDownloadStatus.pending,
              createdAt: now,
            ),
          ),
      throwsA(isA<Object>()),
    );

    // Borrar el archivo se lleva su texto, y la lista queda sin él.
    await db.customStatement("DELETE FROM renditions WHERE id = 'foto'");
    expect(
      await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('texto-foto'))).get(),
      isEmpty,
    );
    final download = await db.select(db.attachmentDownloads).getSingle();
    expect(download.renditionId, isNull);

    // Y borrar el elemento se lleva todo.
    await db.customStatement("DELETE FROM item WHERE id = 'una-pagina'");
    expect(await db.select(db.attachmentDownloads).get(), isEmpty);
    expect(await db.select(db.renditions).get(), isEmpty);
  });

  test('no queda ninguna clave que apunte a algo que no existe', () async {
    final db = await migrateFrom35();

    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
