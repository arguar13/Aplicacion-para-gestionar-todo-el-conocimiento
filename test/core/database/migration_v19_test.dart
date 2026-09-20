import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vault_counts.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v18.dart' as v18;
import '../../support/schema_snapshot.dart';

/// La migración de esquema 18→19 —se suelta el modelo viejo (F10): `items`,
/// `sources`, `tags`, `item_tags` y la columna `source.full_text`—.
///
/// Se siembra la base de v18 (`schemaAt(18)` y las clases generadas de esa
/// versión) con las tablas viejas todavía llenas y recién después se abre
/// `AppDatabase` encima. Lo que se comprueba es lo que le importa a quien tiene
/// una bóveda: que el texto de las fuentes queda exacto —nunca se pierde ni se
/// reescribe—, que ninguna fila de lo que creó se pierde, y que ante un texto
/// que solo estaba en la columna que se quita la migración se corta sin cambiar
/// nada.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  const article = 'La república romana.\n\nEl imperio.';
  const staleTranscript = 'texto viejo de la transcripción';
  const transcript = '[00:00] Hola.\n[00:20] Hoy Roma.';

  /// Un elemento en los dos modelos, con una forma de texto. [fullText] es lo
  /// que tenía la copia que esta migración quita.
  Future<void> seedSource(
    v18.DatabaseAtV18 db,
    String id, {
    required String kind,
    required String renditionKind,
    required String text,
    String fullText = '',
    bool withRendition = true,
  }) async {
    await db
        .into(db.sources)
        .insert(
          v18.SourcesCompanion.insert(
            id: 'src-$id',
            kind: kind,
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v18.ItemsCompanion.insert(
            id: id,
            title: 'Fuente $id',
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
    await db
        .into(db.item)
        .insert(
          v18.ItemCompanion.insert(
            id: id,
            title: 'Fuente $id',
            kind: 'source',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.source)
        .insert(
          v18.SourceCompanion.insert(
            itemId: id,
            sourceType: kind,
            capturedAt: seconds,
            contentHash: '',
            fullText: Value(fullText),
            processingStatus: 'done',
          ),
        );
    if (!withRendition) return;
    await db
        .into(db.renditions)
        .insert(
          v18.RenditionsCompanion.insert(
            id: 'r-$id',
            itemId: id,
            kind: renditionKind,
            content: Value(text),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
  }

  /// Una bóveda como la deja v18, con el modelo viejo todavía lleno: dos
  /// fuentes con su copia en `full_text` —una al día y una vieja—, sus chunks,
  /// una nota, un vínculo, un resaltado, una tarjeta, una etiqueta vieja y su
  /// asignación.
  Future<void> seedVault(v18.DatabaseAtV18 db) async {
    await seedSource(
      db,
      'art',
      kind: 'webPage',
      renditionKind: 'markdown',
      text: article,
      fullText: article,
    );
    await seedSource(
      db,
      'tra',
      kind: 'youtube',
      renditionKind: 'plainText',
      text: transcript,
      fullText: staleTranscript,
    );
    for (final (seq, start, end, content) in [
      (0, 0, 22, 'La república romana.\n\n'),
      (1, 22, 33, 'El imperio.'),
    ]) {
      await db
          .into(db.chunks)
          .insert(
            v18.ChunksCompanion.insert(
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
        .into(db.chunks)
        .insert(
          v18.ChunksCompanion.insert(
            id: 'chunk-tra-0',
            itemId: 'tra',
            seq: 0,
            content: transcript,
            charStart: 0,
            charEnd: transcript.length,
          ),
        );

    await db
        .into(db.sources)
        .insert(
          v18.SourcesCompanion.insert(
            id: 'src-nota',
            kind: 'manualNote',
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v18.ItemsCompanion.insert(
            id: 'nota',
            title: 'Una nota',
            sourceId: 'src-nota',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
    await db
        .into(db.item)
        .insert(
          v18.ItemCompanion.insert(
            id: 'nota',
            title: 'Una nota',
            kind: 'note',
            state: 'processed',
            createdAt: seconds,
            updatedAt: seconds,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.note)
        .insert(
          v18.NoteCompanion.insert(
            itemId: 'nota',
            noteKind: 'living',
            maturity: 'seed',
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          v18.RenditionsCompanion.insert(
            id: 'r-nota',
            itemId: 'nota',
            kind: 'blocks',
            content: const Value('[{"type":"paragraph","text":"Pienso."}]'),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );

    await db
        .into(db.relations)
        .insert(
          v18.RelationsCompanion.insert(
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
          v18.HighlightsCompanion.insert(
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
          v18.FlashcardsCompanion.insert(
            id: 'fc-1',
            itemId: 'art',
            front: '¿Qué?',
            back: 'Eso.',
            dueAt: seconds,
            createdAt: seconds,
          ),
        );
    await db
        .into(db.tags)
        .insert(
          v18.TagsCompanion.insert(
            id: 'tag-1',
            name: 'Roma',
            createdAt: seconds,
          ),
        );
    await db
        .into(db.itemTags)
        .insert(v18.ItemTagsCompanion.insert(itemId: 'art', tagId: 'tag-1'));
  }

  /// Las filas de cada tabla de lo que el usuario creó y del modelo nuevo, en
  /// una base cualquiera.
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

  Future<int> textBytes(GeneratedDatabase db) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(LENGTH(content)), 0) AS n FROM renditions',
              )
              .getSingle())
          .read<int>('n');

  Future<AppDatabase> migrateFrom18({
    Future<void> Function(v18.DatabaseAtV18 oldDb)? seed,
    Map<String, int>? countsBefore,
    List<int>? textBytesBefore,
  }) async {
    final schema = await verifier.schemaAt(18);
    final oldDb = v18.DatabaseAtV18(schema.newConnection());
    if (seed != null) await seed(oldDb);
    countsBefore?.addAll(await countsOf(oldDb));
    textBytesBefore?.add(await textBytes(oldDb));
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<Set<String>> tableNames(AppDatabase db) async => {
    for (final r
        in await db
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .get())
      r.read<String>('name'),
  };

  test('la migración llega a la forma del snapshot de v19', () async {
    await migrateFrom18(seed: seedVault);
    // `migrateAndValidate` ya comparó el esquema contra el snapshot.
    expect(latestSchemaSnapshot, 19);
  });

  group('el modelo viejo', () {
    test('las cuatro tablas dejan de existir', () async {
      final db = await migrateFrom18(seed: seedVault);

      final names = await tableNames(db);

      for (final gone in ['items', 'sources', 'tags', 'item_tags']) {
        expect(names, isNot(contains(gone)), reason: gone);
      }
      // Y lo nuevo sigue.
      expect(names, containsAll(['item', 'source', 'note', 'renditions']));
    });

    test('source deja de tener full_text', () async {
      final db = await migrateFrom18(seed: seedVault);

      final columns = {
        for (final r
            in await db
                .customSelect("SELECT name FROM pragma_table_info('source')")
                .get())
          r.read<String>('name'),
      };

      expect(columns, isNot(contains('full_text')));
      expect(columns, containsAll(['item_id', 'content_hash', 'source_type']));
    });

    test('item recibe los índices de items que las consultas usan', () async {
      final db = await migrateFrom18(seed: seedVault);

      final indexes = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index' "
                  "AND tbl_name = 'item'",
                )
                .get())
          r.read<String>('name'),
      };

      expect(
        indexes,
        containsAll([
          'idx_knowledge_entries_space',
          'idx_knowledge_entries_updated_at',
        ]),
      );
    });

    test('no queda ninguna clave que apunte a algo que no existe', () async {
      final db = await migrateFrom18(seed: seedVault);

      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });
  });

  group('lo que el usuario creó', () {
    test('ninguna fila se pierde ni se inventa', () async {
      final before = <String, int>{};
      final db = await migrateFrom18(seed: seedVault, countsBefore: before);

      expect(await countsOf(db), before);
      // Y no es una comparación de ceros.
      expect(before['item'], 3);
      expect(before['source'], 2);
      expect(before['note'], 1);
      expect(before['renditions'], 3);
      expect(before['chunks'], 3);
      expect(before['relations'], 1);
      expect(before['highlights'], 1);
      expect(before['flashcards'], 1);
    });

    test('el texto de cada fuente queda exacto, y los chunks siguen '
        'reconstruyéndolo', () async {
      final bytes = <int>[];
      final db = await migrateFrom18(seed: seedVault, textBytesBefore: bytes);

      expect(await textBytes(db), bytes.single);
      final art = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();
      expect(art.content, article);
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('; '));
      expect(report.sourcesChecked, 2);
      expect(report.chunksChecked, 3);
    });

    test('una copia vieja en full_text, distinta del texto de la forma '
        'principal, se quita sin tocar el texto que vale', () async {
      final db = await migrateFrom18(seed: seedVault);

      final tra = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-tra'))).getSingle();

      expect(tra.content, transcript);
    });
  });

  group('cuando el texto solo estaba en la columna que se quita', () {
    test('la migración se corta y no cambia nada', () async {
      final schema = await verifier.schemaAt(18);
      final oldDb = v18.DatabaseAtV18(schema.newConnection());
      await seedVault(oldDb);
      // Una fuente con texto en full_text y ninguna forma de texto: soltar la
      // columna perdería ese texto.
      await seedSource(
        oldDb,
        'huerfana',
        kind: 'webPage',
        renditionKind: 'plainText',
        text: '',
        fullText: 'Un texto que no está en ninguna forma.',
        withRendition: false,
      );
      final before = await countsOf(oldDb);
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('v19'), contains('1 fuentes'), contains('No se')),
          ),
        ),
      );
      await db.close();

      // La base quedó como estaba: en v18, con el modelo viejo y el texto.
      final again = v18.DatabaseAtV18(schema.newConnection());
      addTearDown(again.close);
      expect(await countsOf(again), before);
      final stillThere = await again
          .customSelect(
            'SELECT full_text FROM source WHERE item_id = ?',
            variables: [Variable.withString('huerfana')],
          )
          .getSingle();
      expect(
        stillThere.read<String>('full_text'),
        'Un texto que no está en ninguna forma.',
      );
      final version = await again
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 18);
      final legacy = await again
          .customSelect(
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE name = 'items'",
          )
          .getSingle();
      expect(legacy.read<int>('n'), 1);
    });
  });
}
