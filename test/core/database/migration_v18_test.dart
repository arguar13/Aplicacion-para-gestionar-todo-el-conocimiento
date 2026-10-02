import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/repoint_item_references_v18.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v16.dart' as v16;
import '../../support/item_rows.dart';
import '../../support/migration_counts.dart';
import '../../support/schema_snapshot.dart';

/// La migración de esquema 16→18 —las claves foráneas pasan de `items` a
/// `item` y el índice de texto de los elementos se rehace sobre `item` (F10)—.
///
/// Se siembra la base VIEJA (`schemaAt(16)` y las clases generadas de esa
/// versión) y recién después se abre `AppDatabase` encima: son datos de antes
/// de migrar de verdad. Lo que se comprueba es lo que le importa a quien tiene
/// una bóveda: que no se pierde ni se inventa ninguna fila, que las cascadas
/// siguen funcionando pero ahora desde `item`, y que ante un dato que no
/// cierra la migración se corta sin cambiar nada.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  /// Un elemento en el modelo viejo (`items` + `sources`), con una forma de
  /// texto; [mirrored] lo deja además en el nuevo, como lo deja `save()`.
  Future<void> seedItem(
    v16.DatabaseAtV16 db,
    String id, {
    required String kind,
    required String renditionKind,
    required String content,
    bool mirrored = true,
  }) async {
    await db
        .into(db.sources)
        .insert(
          v16.SourcesCompanion.insert(
            id: 'src-$id',
            kind: kind,
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v16.ItemsCompanion.insert(
            id: id,
            title: 'Elemento $id',
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          v16.RenditionsCompanion.insert(
            id: 'r-$id',
            itemId: id,
            kind: renditionKind,
            content: Value(content),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
    if (!mirrored) return;

    final isNote = kind == 'manualNote';
    await db
        .into(db.item)
        .insert(
          v16.ItemCompanion.insert(
            id: id,
            title: 'Elemento $id',
            kind: isNote ? 'note' : 'source',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'test',
          ),
        );
    if (isNote) {
      await db
          .into(db.note)
          .insert(
            v16.NoteCompanion.insert(
              itemId: id,
              noteKind: 'living',
              maturity: 'seed',
            ),
          );
    } else {
      await db
          .into(db.source)
          .insert(
            v16.SourceCompanion.insert(
              itemId: id,
              sourceType: kind,
              capturedAt: seconds,
              contentHash: '',
              fullText: const Value(''),
              processingStatus: 'done',
            ),
          );
    }
  }

  /// Una bóveda como la deja v16: un artículo con un subrayado, un video, una
  /// nota, y una nota SIN espejo en `item` (el catch-up de v18 tiene que
  /// completarla); con vínculos, enlaces en línea, tarjetas, un valor de Tema
  /// puesto en dos elementos y un chunk con su embedding.
  Future<void> seedVault(v16.DatabaseAtV16 db) async {
    await seedItem(
      db,
      'art',
      kind: 'webPage',
      renditionKind: 'markdown',
      content: 'La república romana.',
    );
    await seedItem(
      db,
      'tra',
      kind: 'youtube',
      renditionKind: 'plainText',
      content: '[00:00] Hola.',
    );
    await seedItem(
      db,
      'nota',
      kind: 'manualNote',
      renditionKind: 'blocks',
      content: '[{"type":"paragraph","text":"Pienso en Roma."}]',
    );
    await seedItem(
      db,
      'nota2',
      kind: 'manualNote',
      renditionKind: 'blocks',
      content: '[{"type":"paragraph","text":"Otra nota sin espejo."}]',
      mirrored: false,
    );

    await db
        .into(db.highlights)
        .insert(
          v16.HighlightsCompanion.insert(
            id: 'hl',
            renditionId: 'r-art',
            startOffset: 3,
            endOffset: 11,
            excerpt: 'república',
            createdAt: seconds,
          ),
        );
    for (final (id, from, to, kind) in [
      ('rel-1', 'nota', 'art', 'cites'),
      ('rel-2', 'nota', 'nota2', 'relatedTo'),
      ('rel-3', 'tra', 'art', 'relatedTo'),
    ]) {
      await db
          .into(db.relations)
          .insert(
            v16.RelationsCompanion.insert(
              id: id,
              fromItemId: from,
              toItemId: to,
              kind: kind,
              createdAt: seconds,
            ),
          );
    }
    await db
        .into(db.inlineLink)
        .insert(
          v16.InlineLinkCompanion.insert(
            id: 'il-1',
            fromItemId: 'nota',
            targetTitle: 'Elemento art',
            normalizedTitle: 'elemento art',
            toItemId: const Value('art'),
            createdAt: seconds,
          ),
        );
    await db
        .into(db.inlineLink)
        .insert(
          v16.InlineLinkCompanion.insert(
            id: 'il-2',
            fromItemId: 'nota',
            targetTitle: 'Cartago',
            normalizedTitle: 'cartago',
            createdAt: seconds,
          ),
        );
    for (final (id, itemId) in [('fc-1', 'art'), ('fc-2', 'nota2')]) {
      await db
          .into(db.flashcards)
          .insert(
            v16.FlashcardsCompanion.insert(
              id: id,
              itemId: itemId,
              front: '¿Qué?',
              back: 'Eso.',
              dueAt: seconds,
              createdAt: seconds,
            ),
          );
    }
    await db
        .into(db.propertyDefinitions)
        .insert(
          v16.PropertyDefinitionsCompanion.insert(
            id: 'def-tema',
            name: 'Tema',
            createdAt: seconds,
          ),
        );
    await db
        .into(db.propertyValues)
        .insert(
          v16.PropertyValuesCompanion.insert(
            id: 'val-roma',
            definitionId: 'def-tema',
            value: 'Roma',
            createdAt: seconds,
          ),
        );
    for (final itemId in ['art', 'nota2']) {
      await db
          .into(db.itemPropertyValues)
          .insert(
            v16.ItemPropertyValuesCompanion.insert(
              itemId: itemId,
              propertyValueId: 'val-roma',
            ),
          );
    }
    await db
        .into(db.chunks)
        .insert(
          v16.ChunksCompanion.insert(
            id: 'chunk-art-0',
            itemId: 'art',
            seq: 0,
            content: 'La república romana.',
            charStart: 0,
            charEnd: 20,
          ),
        );
    await db
        .into(db.embeddings)
        .insert(
          v16.EmbeddingsCompanion.insert(
            chunkId: 'chunk-art-0',
            vector: Uint8List.fromList([1, 2, 3, 4]),
            modelVersion: 'modelo',
            createdAt: seconds,
          ),
        );
  }

  /// Las filas de cada tabla de [VaultCounts.userDataTables] en una base
  /// cualquiera, con el mismo criterio que la migración.
  Future<Map<String, int>> countsOf(GeneratedDatabase db) async => {
    for (final table in VaultCounts.userDataTables)
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
  };

  Future<AppDatabase> migrateFrom16({
    Future<void> Function(v16.DatabaseAtV16 oldDb)? seed,
    Map<String, int>? countsBefore,
  }) async {
    final schema = await verifier.schemaAt(16);
    final oldDb = v16.DatabaseAtV16(schema.newConnection());
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

  test('la migración llega a la forma del último snapshot', () async {
    await migrateFrom16(seed: seedVault);
    // `migrateAndValidate` ya comparó el esquema contra el snapshot: la base
    // sembrada en v16 pasa por v18 y llega hasta la versión de hoy.
    expect(latestSchemaSnapshot, greaterThanOrEqualTo(18));
  });

  group('lo que el usuario creó', () {
    test('no pierde ni inventa ninguna fila de ninguna tabla', () async {
      final before = <String, int>{};
      final db = await migrateFrom16(seed: seedVault, countsBefore: before);

      expect(
        withoutAuthorCategory((await captureVaultCounts(db)).rows),
        before,
      );
      // Y no es una comparación de ceros.
      expect(before['renditions'], 4);
      expect(before['relations'], 3);
      expect(before['flashcards'], 2);
      expect(before['inline_link'], 2);
      expect(before['item_property_values'], 2);
      expect(before['highlights'], 1);
      expect(before['embeddings'], 1);
    });

    test('las formas siguen siendo las mismas, con su texto', () async {
      final db = await migrateFrom16(seed: seedVault);

      final rows = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();

      expect(rows.itemId, 'art');
      expect(rows.content, 'La república romana.');
      expect(rows.isPrimary, isTrue);
    });

    test(
      'un enlace en línea roto sigue roto, y el resuelto, resuelto',
      () async {
        final db = await migrateFrom16(seed: seedVault);

        final links = {
          for (final l in await db.select(db.inlineLinks).get())
            l.id: l.toItemId,
        };

        expect(links, {'il-1': 'art', 'il-2': null});
      },
    );
  });

  group('las claves foráneas', () {
    test(
      'apuntan a item, y los subrayados siguen colgando de las formas',
      () async {
        final db = await migrateFrom16(seed: seedVault);

        Future<Set<String>> targets(String table) async => {
          for (final r
              in await db
                  .customSelect(
                    'SELECT "table" AS target FROM pragma_foreign_key_list(?)',
                    variables: [Variable.withString(table)],
                  )
                  .get())
            r.read<String>('target'),
        };

        expect(await targets('renditions'), {'item'});
        // Desde v34 (F27) un vínculo, una tarjeta y una propiedad también
        // pueden apuntar a la pasada de la IA que los hizo.
        expect(await targets('relations'), {'item', 'ai_runs'});
        // Desde v20 una tarjeta también puede apuntar al chunk del que salió.
        expect(await targets('flashcards'), {'item', 'chunks', 'ai_runs'});
        expect(await targets('inline_link'), {'item'});
        expect(await targets('item_property_values'), {
          'item',
          'property_values',
          'ai_runs',
        });
        expect(await targets('highlights'), {'renditions'});
      },
    );

    test('no queda ninguna violación', () async {
      final db = await migrateFrom16(seed: seedVault);

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('borrar la fila de item se lleva a sus dependientes, y deja rotos los '
        'enlaces que apuntaban a él', () async {
      final db = await migrateFrom16(seed: seedVault);

      await (db.delete(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('art'))).go();

      expect(await count(db, 'renditions'), 3);
      expect(await count(db, 'highlights'), 0);
      expect(await count(db, 'flashcards'), 1);
      expect(await count(db, 'item_property_values'), 1);
      expect(await count(db, 'chunks'), 0);
      expect(await count(db, 'embeddings'), 0);
      // Las relaciones donde 'art' era cualquiera de los dos extremos.
      final relations = await db.select(db.relations).get();
      expect(relations.map((r) => r.id), ['rel-2']);
      // El enlace a 'art' vuelve a quedar roto, no desaparece.
      final links = {
        for (final l in await db.select(db.inlineLinks).get()) l.id: l.toItemId,
      };
      expect(links, {'il-1': null, 'il-2': null});
    });

    test('borrar una forma sigue llevándose sus subrayados', () async {
      final db = await migrateFrom16(seed: seedVault);

      await (db.delete(db.renditions)..where((r) => r.id.equals('r-art'))).go();

      expect(await count(db, 'highlights'), 0);
    });
  });

  group('el espejo', () {
    test(
      'lo que faltaba en item se completa, con sus dependientes intactos',
      () async {
        final db = await migrateFrom16(seed: seedVault);

        expect(await count(db, 'item'), 4);
        final entry = await (db.select(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('nota2'))).getSingle();
        expect(entry.title, 'Elemento nota2');
        final note = await (db.select(
          db.knowledgeNotes,
        )..where((n) => n.itemId.equals('nota2'))).getSingleOrNull();
        expect(note, isNotNull);
        // Sus formas, su vínculo y su tarjeta siguen ahí.
        expect(
          (await db.select(db.renditions).get()).map((r) => r.itemId),
          contains('nota2'),
        );
        expect(
          (await db.select(db.flashcards).get()).map((f) => f.itemId),
          contains('nota2'),
        );
      },
    );

    test(
      'una fila de item sin fila en items se conserva y queda informada',
      () async {
        final db = await migrateFrom16(
          seed: (old) async {
            await seedVault(old);
            await old
                .into(old.item)
                .insert(
                  v16.ItemCompanion.insert(
                    id: 'fantasma',
                    title: 'Sin origen',
                    kind: 'source',
                    state: 'captured',
                    createdAt: seconds,
                    updatedAt: seconds,
                    deviceId: 'test',
                  ),
                );
          },
        );

        expect(
          await (db.select(
            db.knowledgeEntries,
          )..where((e) => e.id.equals('fantasma'))).getSingleOrNull(),
          isNotNull,
        );
        final issues = await (db.select(
          db.migrationIssues,
        )..where((i) => i.migration.equals('f10_v18'))).get();
        expect(issues.map((i) => (i.itemId, i.stage)), [
          ('fantasma', 'item_without_legacy_row'),
        ]);
      },
    );
  });

  group('el índice de texto de los elementos', () {
    test('queda con una entrada por elemento de item, y con sus triggers en '
        'item', () async {
      final db = await migrateFrom16(seed: seedVault);

      expect(await count(db, 'item_search'), await count(db, 'item'));
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND tbl_name = 'item'",
          )
          .get();
      expect(
        triggers.map((r) => r.read<String>('name')).toSet(),
        containsAll(['entry_search_ai', 'entry_search_au', 'entry_search_ad']),
      );
    });

    test('una nota que se guarda después de migrar es buscable por su texto: '
        'las formas reconstruidas conservan su trigger', () async {
      final db = await migrateFrom16(seed: seedVault);

      await db
          .into(db.renditions)
          .insert(
            RenditionsCompanion.insert(
              id: 'r-extra',
              itemId: 'nota',
              kind: RenditionKind.plainText,
              isPrimary: false,
              createdAt: DateTime(2026, 9, 20),
              content: const Value('Y además pienso en Kuhn.'),
            ),
          );

      final rows = await db
          .customSelect(
            'SELECT item_id FROM item_search WHERE item_search MATCH ?',
            variables: [Variable.withString('"kuhn"')],
          )
          .get();
      expect(rows.map((r) => r.read<String>('item_id')), ['nota']);
    });
  });

  group('cuando la bóveda no cierra', () {
    test('una fila que apunta a un elemento que no existe corta la migración '
        'y no cambia nada', () async {
      final schema = await verifier.schemaAt(16);
      final oldDb = v16.DatabaseAtV16(schema.newConnection());
      await seedVault(oldDb);
      // Un vínculo hacia un elemento que ni en items ni en item existe: el
      // motor viejo lo permitió mientras las claves estuvieron apagadas.
      await oldDb
          .into(oldDb.relations)
          .insert(
            v16.RelationsCompanion.insert(
              id: 'rel-huerfana',
              fromItemId: 'art',
              toItemId: 'nadie',
              kind: 'relatedTo',
              createdAt: seconds,
            ),
          );
      final before = await countsOf(oldDb);
      final itemsBefore = (await oldDb.select(oldDb.item).get()).length;
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('v18'), contains('relations.to_item_id=1')),
          ),
        ),
      );
      await db.close();

      // La base quedó como estaba: mismas filas, sin el espejo que el catch-up
      // había completado antes de detectar el huérfano, y todavía en v16.
      final again = v16.DatabaseAtV16(schema.newConnection());
      addTearDown(again.close);
      expect(await countsOf(again), before);
      expect((await again.select(again.item).get()).length, itemsBefore);
      final version = await again
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 16);
    });
  });

  group('el plan (dry-run)', () {
    /// `items` ya no existe en el esquema de hoy —F10 la retiró—, pero el plan
    /// corre contra bases que todavía la tienen y solo le pide los ids: se arma
    /// esa parte.
    Future<AppDatabase> databaseWithLegacyItems(List<String> legacyIds) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('CREATE TABLE items (id TEXT PRIMARY KEY)');
      for (final id in legacyIds) {
        await db.customStatement('INSERT INTO items (id) VALUES (?)', [id]);
      }
      return db;
    }

    test('cuenta lo que encuentra y no escribe nada', () async {
      final db = await databaseWithLegacyItems(['ok', 'solo-viejo']);
      final now = DateTime(2026, 9, 20);
      await insertItemRows(db, id: 'ok', title: 'Completo', createdAt: now);
      // Solo en el nuevo.
      await db
          .into(db.knowledgeEntries)
          .insert(
            KnowledgeEntriesCompanion.insert(
              id: 'solo-nuevo',
              title: 'Solo en item',
              kind: ItemKind.source,
              state: ItemState.captured,
              createdAt: now,
              updatedAt: now,
              deviceId: 'test',
            ),
          );
      // Un vínculo hacia un elemento que no existe: con las claves apagadas.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await db
          .into(db.relations)
          .insert(
            RelationsCompanion.insert(
              id: 'rel-huerfana',
              fromItemId: 'ok',
              toItemId: 'nadie',
              kind: RelationKind.relatedTo,
              createdAt: now,
            ),
          );
      await db.customStatement('PRAGMA foreign_keys = ON');
      final tables = [...VaultCounts.userDataTables, 'item', 'items'];
      final before = await captureVaultCounts(db, tables: tables);

      final plan = await planItemReferenceRepoint(db);

      expect(plan.unmirrored, ['solo-viejo']);
      expect(plan.ghosts, ['solo-nuevo']);
      expect(plan.orphans['relations.to_item_id'], 1);
      expect(plan.orphans['relations.from_item_id'], 0);
      expect(plan.canProceed, isFalse);
      expect(plan.summary(), contains('relations.to_item_id=1'));
      // Calcular el plan no escribió nada.
      final after = await captureVaultCounts(db, tables: tables);
      expect(after.rows, before.rows);
    });

    test('una bóveda completa puede seguir', () async {
      final db = await databaseWithLegacyItems(['a', 'b']);
      await insertItemRows(db, id: 'a', title: 'A');
      await insertItemRows(db, id: 'b', title: 'B');

      final plan = await planItemReferenceRepoint(db);

      expect(plan.canProceed, isTrue);
      expect(plan.items, 2);
      expect(plan.entries, 2);
      expect(plan.unmirrored, isEmpty);
      expect(plan.ghosts, isEmpty);
    });
  });

  group('VaultCounts', () {
    test('dice qué tablas cambiaron, con el antes y el después', () {
      const before = VaultCounts({'a': 1, 'b': 2, 'c': 3});
      const after = VaultCounts({'a': 1, 'b': 5, 'c': 0});

      expect(before.differencesWith(after), {'b': (2, 5), 'c': (3, 0)});
      expect(before.differencesWith(before), isEmpty);
    });
  });
}
