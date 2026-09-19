import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v13.dart' as v13;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 14→15 —enlaces en línea, contradicciones revisadas
/// y procedencia de las citas (F9): la tabla `inline_link` y tres columnas
/// anulables en `Relations`—, más el registro de los `[[Título]]` de las notas
/// que ya existían.
///
/// Se siembra la base VIEJA (`schemaAt(13)` y las clases generadas de esa
/// versión) y recién después se abre `AppDatabase` encima: son datos de antes
/// de migrar de verdad. Arranca en 13, no en 14, porque v13→v14 no cambió la
/// forma del esquema y no hay snapshot de v14.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  Future<void> seedItem(
    v13.DatabaseAtV13 db,
    String id,
    String title, {
    int createdAt = seconds,
  }) async {
    await db
        .into(db.sources)
        .insert(
          v13.SourcesCompanion.insert(
            id: 'src-$id',
            kind: 'webPage',
            capturedAt: createdAt,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v13.ItemsCompanion.insert(
            id: id,
            title: title,
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }

  Future<void> addBlocks(v13.DatabaseAtV13 db, String itemId, String content) =>
      db
          .into(db.renditions)
          .insert(
            v13.RenditionsCompanion.insert(
              id: 'r-$itemId',
              itemId: itemId,
              kind: 'blocks',
              content: Value(content),
              // El snapshot guarda los booleanos como enteros.
              isPrimary: 1,
              createdAt: seconds,
            ),
          );

  Future<void> seedNote(
    v13.DatabaseAtV13 db,
    String id,
    String title,
    String text,
  ) async {
    await seedItem(db, id, title);
    await addBlocks(
      db,
      id,
      encodeContentBlocks([ContentBlock.paragraph(text: text)]),
    );
  }

  /// Una bóveda como la deja la app de antes de F9: un elemento "Roma", una
  /// nota que lo enlaza y además enlaza a una nota que nunca se creó.
  Future<void> seedPreF9Vault(v13.DatabaseAtV13 db) async {
    await seedItem(db, 'roma', 'Roma');
    await seedNote(db, 'n1', 'Viaje', 'Fui a [[Roma]] y a [[Cartago]].');
  }

  /// Deja una base en v13 con lo que siembre [seed], la abre con
  /// `AppDatabase` —lo que la migra— y comprueba que la forma resultante es la
  /// del snapshot más reciente.
  Future<AppDatabase> migrateFrom13({
    Future<void> Function(v13.DatabaseAtV13 oldDb)? seed,
  }) async {
    final schema = await verifier.schemaAt(13);
    final oldDb = v13.DatabaseAtV13(schema.newConnection());
    if (seed != null) await seed(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  test('una base nueva (onCreate) trae inline_link vacía', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await db.select(db.inlineLinks).get(), isEmpty);
  });

  test('migrar de v13 a v15 deja la forma del snapshot y registra los enlaces '
      'de las notas existentes', () async {
    final db = await migrateFrom13(seed: seedPreF9Vault);

    final links = await db.select(db.inlineLinks).get();
    expect(
      {for (final l in links) (l.fromItemId, l.normalizedTitle, l.toItemId)},
      {('n1', 'roma', 'roma'), ('n1', 'cartago', null)},
    );
    // Se conserva el título como se escribió: con él se crea la nota que
    // falta.
    expect(links.map((l) => l.targetTitle).toSet(), {'Roma', 'Cartago'});
  });

  test('deja en MigrationIssues el enlace roto, y solo ese', () async {
    final db = await migrateFrom13(seed: seedPreF9Vault);

    final report = await (db.select(
      db.migrationIssues,
    )..where((i) => i.migration.equals('f9_inline_links'))).get();
    expect(report.map((r) => (r.stage, r.itemId)), [
      ('broken_inline_link', 'n1'),
    ]);
    expect(report.single.message, contains('[[Cartago]]'));
  });

  test('no crea relaciones al registrar los enlaces', () async {
    final db = await migrateFrom13(seed: seedPreF9Vault);

    expect(await db.select(db.relations).get(), isEmpty);
  });

  test('las relaciones anteriores se conservan, con las columnas nuevas en '
      'null', () async {
    final db = await migrateFrom13(
      seed: (oldDb) async {
        await seedItem(oldDb, 'a', 'A');
        await seedItem(oldDb, 'b', 'B');
        await oldDb
            .into(oldDb.relations)
            .insert(
              v13.RelationsCompanion.insert(
                id: 'rel-1',
                fromItemId: 'a',
                toItemId: 'b',
                kind: 'contradicts',
                note: const Value('choca con B'),
                createdAt: seconds,
              ),
            );
      },
    );

    final relation = await db.select(db.relations).getSingle();
    expect(relation.id, 'rel-1');
    expect(relation.note, 'choca con B');
    expect(relation.reviewedAt, isNull);
    expect(relation.sourceCharStart, isNull);
    expect(relation.sourceCharEnd, isNull);
  });

  test('una bóveda sin notas migra sin enlaces ni informe', () async {
    final db = await migrateFrom13(
      seed: (oldDb) => seedItem(oldDb, 'i1', 'Un elemento'),
    );

    expect(await db.select(db.inlineLinks).get(), isEmpty);
    final report = await (db.select(
      db.migrationIssues,
    )..where((i) => i.migration.equals('f9_inline_links'))).get();
    expect(report, isEmpty);
  });

  test('una nota con bloques ilegibles no hace fallar la migración: se '
      'informa', () async {
    final db = await migrateFrom13(
      seed: (oldDb) async {
        await seedPreF9Vault(oldDb);
        await seedItem(oldDb, 'mala', 'Nota rota');
        await addBlocks(oldDb, 'mala', 'esto no es json');
      },
    );

    // La nota legible sigue registrando sus enlaces.
    expect(await db.select(db.inlineLinks).get(), hasLength(2));
    final report = await (db.select(
      db.migrationIssues,
    )..where((i) => i.stage.equals('unreadable_blocks'))).get();
    expect(report.map((r) => r.itemId), ['mala']);
  });
}
