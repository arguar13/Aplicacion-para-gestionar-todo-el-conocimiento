import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/active_entries.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v19.dart' as v19;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 19→20 —durabilidad (F11)—: la versión por campo, los
/// conflictos de fusión, el historial de repasos, de dónde salió cada tarjeta y
/// un índice para la papelera.
///
/// Es aditiva: tablas nuevas y columnas nulas. Se siembra la base de v19 (con
/// `schemaAt(19)` y las clases generadas de esa versión) y recién después se
/// abre `AppDatabase` encima. Lo que se comprueba es que no cambia ninguna fila
/// de nada de lo que había, que las tablas nuevas nacen vacías y con las claves
/// que dicen, y que sus cascadas funcionan.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.
  const article = 'La república romana.\n\nEl imperio.';

  /// Una bóveda como la deja v19: una fuente con su forma de texto y sus
  /// chunks, una nota, un vínculo, un resaltado y una tarjeta.
  Future<void> seedVault(v19.DatabaseAtV19 db) async {
    for (final (id, kind, isNote) in [
      ('art', 'webPage', false),
      ('nota', 'manualNote', true),
    ]) {
      await db
          .into(db.item)
          .insert(
            v19.ItemCompanion.insert(
              id: id,
              title: 'Elemento $id',
              kind: isNote ? 'note' : 'source',
              state: 'processed',
              createdAt: seconds,
              updatedAt: seconds,
              deviceId: 'f3-espejo-sin-sync',
            ),
          );
      if (isNote) {
        await db
            .into(db.note)
            .insert(
              v19.NoteCompanion.insert(
                itemId: id,
                noteKind: 'living',
                maturity: 'seed',
              ),
            );
      } else {
        await db
            .into(db.source)
            .insert(
              v19.SourceCompanion.insert(
                itemId: id,
                sourceType: kind,
                capturedAt: seconds,
                contentHash: '',
                processingStatus: 'done',
              ),
            );
      }
    }
    await db
        .into(db.renditions)
        .insert(
          v19.RenditionsCompanion.insert(
            id: 'r-art',
            itemId: 'art',
            kind: 'markdown',
            content: const Value(article),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
    for (final (seq, start, end, content) in [
      (0, 0, 22, 'La república romana.\n\n'),
      (1, 22, 33, 'El imperio.'),
    ]) {
      await db
          .into(db.chunks)
          .insert(
            v19.ChunksCompanion.insert(
              id: 'chunk-art-$seq',
              itemId: 'art',
              seq: seq,
              content: content,
              charStart: start,
              charEnd: end,
            ),
          );
    }
    await db
        .into(db.relations)
        .insert(
          v19.RelationsCompanion.insert(
            id: 'rel-1',
            fromItemId: 'nota',
            toItemId: 'art',
            kind: 'cites',
            createdAt: seconds,
          ),
        );
    await db
        .into(db.highlights)
        .insert(
          v19.HighlightsCompanion.insert(
            id: 'hl-1',
            renditionId: 'r-art',
            startOffset: 3,
            endOffset: 11,
            excerpt: 'república',
            createdAt: seconds,
          ),
        );
    await db
        .into(db.flashcards)
        .insert(
          v19.FlashcardsCompanion.insert(
            id: 'fc-1',
            itemId: 'art',
            front: '¿Qué?',
            back: 'Eso.',
            dueAt: seconds,
            createdAt: seconds,
          ),
        );
  }

  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in [
      ...VaultCounts.userDataTables,
      ...VaultCounts.modelTables,
    ])
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom19({
    Future<void> Function(v19.DatabaseAtV19 oldDb)? seed,
    Map<String, int>? countsBefore,
  }) async {
    final schema = await verifier.schemaAt(19);
    final oldDb = v19.DatabaseAtV19(schema.newConnection());
    if (seed != null) await seed(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<int> count(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<Set<String>> namesOf(AppDatabase db, String sql) async => {
    for (final r in await db.customSelect(sql).get()) r.read<String>('name'),
  };

  test('la migración llega a la forma del snapshot de v20', () async {
    await migrateFrom19(seed: seedVault);
    // `migrateAndValidate` ya comparó el esquema contra el snapshot.
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(20));
  });

  group('lo que había', () {
    test('no cambia ninguna fila de ninguna tabla', () async {
      final before = <String, int>{};
      final db = await migrateFrom19(seed: seedVault, countsBefore: before);

      expect(await countsOf(db), before);
      // Y no es una comparación de ceros.
      expect(before['item'], 2);
      expect(before['renditions'], 1);
      expect(before['chunks'], 2);
      expect(before['flashcards'], 1);
    });

    test('el texto de la fuente y sus chunks quedan exactos', () async {
      final db = await migrateFrom19(seed: seedVault);

      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();

      expect(rendition.content, article);
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('; '));
      expect(report.chunksChecked, 2);
    });

    test('una tarjeta que ya existía queda sin fragmento de origen', () async {
      final db = await migrateFrom19(seed: seedVault);

      final card = await (db.select(
        db.flashcards,
      )..where((f) => f.id.equals('fc-1'))).getSingle();

      expect(card.front, '¿Qué?');
      expect(card.sourceChunkId, isNull);
      expect(card.sourceCharStart, isNull);
      expect(card.sourceCharEnd, isNull);
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      final db = await migrateFrom19(seed: seedVault);

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('lo nuevo', () {
    test('las tablas de durabilidad nacen vacías', () async {
      final db = await migrateFrom19(seed: seedVault);

      for (final table in VaultCounts.durabilityTables) {
        expect(await count(db, table), 0, reason: table);
      }
    });

    test(
      'field_version guarda el linaje: la versión sobre la que se editó',
      () async {
        final db = await migrateFrom19(seed: seedVault);

        final columns = await namesOf(
          db,
          "SELECT name FROM pragma_table_info('field_version')",
        );

        expect(
          columns,
          containsAll([
            'item_id',
            'field_name',
            'updated_at',
            'device_id',
            'base_updated_at',
            'base_device_id',
          ]),
        );
      },
    );

    test('los índices existen', () async {
      final db = await migrateFrom19(seed: seedVault);

      final indexes = await namesOf(
        db,
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(
        indexes,
        containsAll([
          'idx_item_trashed',
          'idx_merge_conflict_resolved',
          'idx_merge_conflict_item',
          'idx_review_log_flashcard',
        ]),
      );
    });

    test('el índice de la papelera es parcial, y el común que tuvo v20 no '
        'queda', () async {
      final db = await migrateFrom19(seed: seedVault);

      final sql =
          (await db
                  .customSelect(
                    'SELECT sql FROM sqlite_master '
                    "WHERE name = 'idx_item_trashed'",
                  )
                  .getSingle())
              .read<String>('sql');

      expect(sql, contains('WHERE deleted_at IS NOT NULL'));
      expect(
        await namesOf(
          db,
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_knowledge_entries_deleted_at'",
        ),
        isEmpty,
      );
    });

    test('una base que ya tenía el índice común de v20 lo cambia por el '
        'parcial al abrirse', () async {
      final db = await migrateFrom19(seed: seedVault);
      await db.customStatement('DROP INDEX idx_item_trashed');
      await db.customStatement(
        'CREATE INDEX idx_knowledge_entries_deleted_at ON item (deleted_at)',
      );

      // `beforeOpen` corre en cada apertura: se simula abriendo de nuevo.
      await db.customStatement(dropSupersededTrashIndex);
      await db.customStatement(createTrashIndex);

      expect(
        await namesOf(
          db,
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
          "('idx_item_trashed', 'idx_knowledge_entries_deleted_at')",
        ),
        {'idx_item_trashed'},
      );
    });

    test(
      'la papelera se busca por su índice y lo vivo NO: el índice común '
      'habría recorrido los diez mil elementos para pedir uno por su id',
      () async {
        final db = await migrateFrom19(seed: seedVault);
        Future<String> planOf(String sql) async => [
          for (final row
              in await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
            row.read<String>('detail'),
        ].join(' | ');

        final trash = await planOf(
          'SELECT ti.id FROM item ti WHERE ti.deleted_at IS NOT NULL',
        );
        final live = await planOf(
          'SELECT id FROM item WHERE deleted_at IS NULL '
          "AND id IN ('art', 'nota')",
        );

        expect(trash, contains('idx_item_trashed'), reason: trash);
        expect(live, isNot(contains('idx_item_trashed')), reason: live);
        expect(live, contains('sqlite_autoindex_item_1'), reason: live);
      },
    );

    test('las claves apuntan a lo que dicen', () async {
      final db = await migrateFrom19(seed: seedVault);

      Future<Set<String>> targets(String table) => namesOf(
        db,
        'SELECT "table" AS name FROM pragma_foreign_key_list(\'$table\')',
      );

      expect(await targets('field_version'), {'item'});
      expect(await targets('merge_conflict'), {'item', 'renditions'});
      expect(await targets('review_log'), {'flashcards'});
      expect(await targets('flashcards'), {'item', 'chunks'});
    });
  });

  group('las cascadas', () {
    test(
      'borrar un elemento se lleva su versión por campo y sus conflictos',
      () async {
        final db = await migrateFrom19(seed: seedVault);
        final at = DateTime(2026, 9, 20);
        await db
            .into(db.fieldVersions)
            .insert(
              FieldVersionsCompanion.insert(
                itemId: 'art',
                fieldName: 'title',
                updatedAt: at,
                deviceId: 'a',
              ),
            );
        await db
            .into(db.mergeConflicts)
            .insert(
              MergeConflictsCompanion.insert(
                id: 'c1',
                itemId: 'art',
                fieldName: 'title',
                detectedAt: at,
              ),
            );

        await (db.delete(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('art'))).go();

        expect(await count(db, 'field_version'), 0);
        expect(await count(db, 'merge_conflict'), 0);
      },
    );

    test('borrar una tarjeta se lleva su historial de repasos', () async {
      final db = await migrateFrom19(seed: seedVault);
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: 'rv1',
              flashcardId: 'fc-1',
              reviewedAt: DateTime(2026, 9, 20),
              grade: 'good',
              quality: 4,
              intervalBefore: 1,
              intervalAfter: 6,
              easeBefore: 2.5,
              easeAfter: 2.5,
              deviceId: 'a',
            ),
          );

      await (db.delete(db.flashcards)..where((f) => f.id.equals('fc-1'))).go();

      expect(await count(db, 'review_log'), 0);
    });

    test('rehacer los chunks deja la tarjeta viva y sin fragmento: no se '
        'borra', () async {
      final db = await migrateFrom19(seed: seedVault);
      await (db.update(db.flashcards)..where((f) => f.id.equals('fc-1'))).write(
        const FlashcardsCompanion(
          sourceChunkId: Value('chunk-art-0'),
          sourceCharStart: Value(0),
          sourceCharEnd: Value(22),
        ),
      );

      await (db.delete(db.chunks)..where((c) => c.itemId.equals('art'))).go();

      final card = await (db.select(
        db.flashcards,
      )..where((f) => f.id.equals('fc-1'))).getSingle();
      expect(card.sourceChunkId, isNull);
      // El rango de caracteres no depende de los chunks: sigue.
      expect(card.sourceCharStart, 0);
      expect(card.sourceCharEnd, 22);
    });
  });
}
