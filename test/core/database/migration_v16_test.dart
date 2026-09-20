import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/migrations/backfill_chunks_v16.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/source_processing_status.dart';
import 'package:sinapsis/core/logging/app_logger.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v15.dart' as v15;
import '../../support/fake_id_generator.dart';
import '../../support/schema_snapshot.dart';

class _SilentLogger implements AppLogger {
  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {}
  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {}
  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {}
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
  @override
  void fatal(String message, [Object? error, StackTrace? stackTrace]) {}
}

/// La migración de esquema 15→16 —chunks vivos y búsqueda por chunks (F10)—:
/// `chunk` gana una clave entera propia, `item` gana `notes`, se fragmenta toda
/// fuente que no lo estaba y se construye el índice de texto de los chunks.
///
/// Se siembra la base VIEJA (`schemaAt(15)` y las clases generadas de esa
/// versión) y recién después se abre `AppDatabase` encima: son datos de antes
/// de migrar de verdad.
void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  const seconds = 1789000000; // 2026-09, en segundos: como guarda drift.

  const article =
      '# Roma\n\nLa república nació en 509 a.C.\n\nEl imperio en 27 a.C.\n\n'
      'Cierre sin salto final';
  const transcript =
      '[00:00] Hola a todos.\n[00:20] Hoy hablamos de Egipto y de Roma.\n'
      '[00:40] Fin.';

  /// Un elemento con su fuente, en los dos modelos, como los deja `save()`.
  Future<void> seedSource(
    v15.DatabaseAtV15 db,
    String id, {
    required String kind,
    String? text,
    String? renditionKind,
    String? relativePath,
    String contentHash = '',
    String? notes,
  }) async {
    await db
        .into(db.sources)
        .insert(
          v15.SourcesCompanion.insert(
            id: 'src-$id',
            kind: kind,
            capturedAt: seconds,
          ),
        );
    await db
        .into(db.items)
        .insert(
          v15.ItemsCompanion.insert(
            id: id,
            title: 'Fuente $id',
            sourceId: 'src-$id',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
            notes: Value(notes),
          ),
        );
    await db
        .into(db.renditions)
        .insert(
          v15.RenditionsCompanion.insert(
            id: 'r-$id',
            itemId: id,
            kind: renditionKind ?? 'markdown',
            content: Value(text),
            relativePath: Value(relativePath),
            isPrimary: 1,
            createdAt: seconds,
          ),
        );
    await db
        .into(db.item)
        .insert(
          v15.ItemCompanion.insert(
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
          v15.SourceCompanion.insert(
            itemId: id,
            sourceType: kind,
            capturedAt: seconds,
            contentHash: contentHash,
            fullText: Value(contentHash.isEmpty ? '' : text ?? ''),
            processingStatus: 'done',
          ),
        );
  }

  /// Una bóveda como la deja la app de antes de F10: dos fuentes que `save()`
  /// nunca fragmentó, una que sí (con un embedding colgando de uno de sus
  /// chunks), una sin texto todavía y una nota.
  Future<void> seedPreF10Vault(v15.DatabaseAtV15 db) async {
    await seedSource(db, 'art', kind: 'webPage', text: article, notes: 'ojo');
    await seedSource(db, 'tra', kind: 'youtube', text: transcript);
    await seedSource(
      db,
      'ya',
      kind: 'webPage',
      text: 'Un párrafo.\n\nOtro párrafo.',
      contentHash: 'hash-de-antes',
    );
    for (final (seq, start, end, content) in [
      (0, 0, 13, 'Un párrafo.\n\n'),
      (1, 13, 26, 'Otro párrafo.'),
    ]) {
      await db
          .into(db.chunks)
          .insert(
            v15.ChunksCompanion.insert(
              id: 'chunk-ya-$seq',
              itemId: 'ya',
              seq: seq,
              content: content,
              charStart: start,
              charEnd: end,
            ),
          );
    }
    await db
        .into(db.embeddings)
        .insert(
          v15.EmbeddingsCompanion.insert(
            chunkId: 'chunk-ya-1',
            vector: Uint8List.fromList([1, 2, 3, 4]),
            modelVersion: 'modelo-de-antes',
            createdAt: seconds,
          ),
        );
    await seedSource(
      db,
      'pdf',
      kind: 'document',
      renditionKind: 'pdf',
      relativePath: 'files/x.pdf',
    );

    await db
        .into(db.items)
        .insert(
          v15.ItemsCompanion.insert(
            id: 'nota',
            title: 'Una nota',
            sourceId: 'src-art',
            processingState: 'ready',
            createdAt: seconds,
            updatedAt: seconds,
          ),
        );
    await db
        .into(db.item)
        .insert(
          v15.ItemCompanion.insert(
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
          v15.NoteCompanion.insert(
            itemId: 'nota',
            noteKind: 'living',
            maturity: 'seed',
          ),
        );
  }

  Future<AppDatabase> migrateFrom15({
    Future<void> Function(v15.DatabaseAtV15 oldDb)? seed,
  }) async {
    final schema = await verifier.schemaAt(15);
    final oldDb = v15.DatabaseAtV15(schema.newConnection());
    if (seed != null) await seed(oldDb);
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latestSchemaSnapshot);
    return db;
  }

  Future<List<String>> searchChunks(AppDatabase db, String term) async {
    final rows = await db
        .customSelect(
          'SELECT chunks.id AS id FROM chunk_search '
          'JOIN chunks ON chunks.row_key = chunk_search.rowid '
          'WHERE chunk_search MATCH ? ORDER BY chunks.id',
          variables: [Variable.withString('"$term"')],
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  group('una base nueva (onCreate)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'trae el índice de texto de los chunks, vacío y funcionando',
      () async {
        expect(await db.select(db.chunks).get(), isEmpty);
        expect(await searchChunks(db, 'roma'), isEmpty);
      },
    );
  });

  group('migrar de v15 a v16', () {
    test('deja la forma del snapshot y fragmenta lo que no estaba fragmentado '
        'sin tocar el texto', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      final chunked = await db.select(db.chunks).get();
      expect(
        {for (final c in chunked) c.itemId}.difference({'art', 'tra', 'ya'}),
        isEmpty,
        reason: 'la nota y la fuente sin texto no tienen chunks',
      );
      expect({for (final c in chunked) c.itemId}, {'art', 'tra', 'ya'});

      // El invariante central: los chunks reconstruyen el texto de cada fuente.
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('\n'));
      expect(report.sourcesChecked, 3);

      // El texto de las fuentes no se tocó.
      final rendition = await (db.select(
        db.renditions,
      )..where((r) => r.id.equals('r-art'))).getSingle();
      expect(rendition.content, article);
    });

    test('la fuente que ya tenía chunks conserva los mismos, con sus ids, y '
        'su embedding sigue colgando de su chunk', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      final chunks = await (db.select(
        db.chunks,
      )..where((c) => c.itemId.equals('ya'))).get();
      expect(chunks.map((c) => c.id), ['chunk-ya-0', 'chunk-ya-1']);

      final embedding = await db.select(db.embeddings).getSingle();
      expect(embedding.chunkId, 'chunk-ya-1');
      expect(embedding.modelVersion, 'modelo-de-antes');
      final orphans = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(orphans, isEmpty);
    });

    test('cada chunk tiene su clave entera, sin repetir', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      final keys = [for (final c in await db.select(db.chunks).get()) c.rowKey];
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys.every((k) => k >= 1), isTrue);
    });

    test(
      'el índice de texto encuentra el texto y vuelve al chunk correcto',
      () async {
        final db = await migrateFrom15(seed: seedPreF10Vault);

        final ids = await searchChunks(db, 'egipto');
        expect(ids, hasLength(1));
        final chunk = await (db.select(
          db.chunks,
        )..where((c) => c.id.equals(ids.single))).getSingle();
        expect(chunk.itemId, 'tra');
        expect(chunk.content, contains('Egipto'));
        // Y con la marca de tiempo de la transcripción.
        expect(chunk.startMs, isNotNull);

        // Sin acentos ni mayúsculas, como el índice de siempre.
        expect(await searchChunks(db, 'republica'), hasLength(1));
        expect(await searchChunks(db, 'PÁRRAFO'), hasLength(2));
      },
    );

    test('el vocabulario dice en cuántos chunks está cada palabra', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      final row = await db
          .customSelect("SELECT doc FROM chunk_vocab WHERE term = 'parrafo'")
          .getSingle();
      expect(row.read<int>('doc'), 2);
    });

    test('copia el texto libre de Items.notes a item.notes', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('art'))).getSingle();
      expect(entry.notes, 'ojo');
      final other = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('tra'))).getSingle();
      expect(other.notes, isNull);
    });

    test('las notas y las fuentes sin texto no reciben chunks, y no hay nada '
        'en MigrationIssues', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);

      expect(
        await (db.select(
          db.chunks,
        )..where((c) => c.itemId.isIn(['nota', 'pdf']))).get(),
        isEmpty,
      );
      expect(await db.select(db.migrationIssues).get(), isEmpty);
    });

    test('una bóveda vacía migra sin nada que hacer', () async {
      final db = await migrateFrom15();

      expect(await db.select(db.chunks).get(), isEmpty);
    });

    test('sobrevive a VACUUM INTO —lo que hacen los respaldos— sin que el '
        'índice apunte a otra fila', () async {
      final db = await migrateFrom15(seed: seedPreF10Vault);
      final before = await searchChunks(db, 'egipto');

      final dir = Directory.systemTemp.createTempSync('v16_vacuum');
      addTearDown(() => dir.deleteSync(recursive: true));
      final copy = File('${dir.path}/copia.sqlite');
      await db.customStatement("VACUUM INTO '${copy.path}'");

      final restored = AppDatabase(NativeDatabase(copy));
      addTearDown(restored.close);
      expect(await searchChunks(restored, 'egipto'), before);
      // Y el texto que el índice devuelve es el de ese chunk.
      final chunk = await (restored.select(
        restored.chunks,
      )..where((c) => c.id.equals(before.single))).getSingle();
      expect(chunk.content, contains('Egipto'));
    });
  });

  group('el índice de texto de los chunks se mantiene solo', () {
    late AppDatabase db;
    late FakeIdGenerator ids;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      ids = FakeIdGenerator(prefix: 'c');
      await db
          .into(db.knowledgeEntries)
          .insert(
            KnowledgeEntriesCompanion.insert(
              id: 'x',
              title: 'Una fuente',
              kind: ItemKind.source,
              state: ItemState.processed,
              createdAt: DateTime(2026, 9, 19),
              updatedAt: DateTime(2026, 9, 19),
              deviceId: 'test',
            ),
          );
    });

    tearDown(() => db.close());

    Future<void> addChunk(int seq, String content) => db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: ids.next(),
            itemId: 'x',
            seq: seq,
            content: content,
            charStart: 0,
            charEnd: content.length,
          ),
        );

    test('un chunk nuevo se encuentra', () async {
      await addChunk(0, 'la república romana');

      expect(await searchChunks(db, 'republica'), hasLength(1));
    });

    test('un chunk que cambia de texto deja de encontrarse por el viejo y se '
        'encuentra por el nuevo', () async {
      await addChunk(0, 'la república romana');
      await (db.update(db.chunks)..where((c) => c.seq.equals(0))).write(
        const ChunksCompanion(content: Value('el imperio de oriente')),
      );

      expect(await searchChunks(db, 'republica'), isEmpty);
      expect(await searchChunks(db, 'imperio'), hasLength(1));
    });

    test(
      'borrar el elemento borra sus chunks en cascada y del índice',
      () async {
        await addChunk(0, 'la república romana');
        await addChunk(1, 'el imperio de oriente');

        await (db.delete(
          db.knowledgeEntries,
        )..where((e) => e.id.equals('x'))).go();

        expect(await db.select(db.chunks).get(), isEmpty);
        expect(await searchChunks(db, 'republica'), isEmpty);
        final indexed = await db
            .customSelect('SELECT COUNT(*) AS n FROM chunk_search_docsize')
            .getSingle();
        expect(indexed.read<int>('n'), 0);
      },
    );
  });

  group('el paso de la migración, por sí solo', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> seedUnchunked() async {
      // Directo en las tablas, como las dejó una app anterior: fuentes con
      // texto y sin chunks.
      for (final (id, text) in [('a', 'Uno.\n\nDos.'), ('b', 'Tres.')]) {
        final now = DateTime(2026, 9, 19);
        await db
            .into(db.sources)
            .insert(
              SourcesCompanion.insert(
                id: 'src-$id',
                kind: SourceKind.webPage,
                capturedAt: now,
              ),
            );
        await db
            .into(db.items)
            .insert(
              ItemsCompanion.insert(
                id: id,
                title: 'Fuente $id',
                sourceId: 'src-$id',
                processingState: ProcessingState.ready,
                createdAt: now,
                updatedAt: now,
                notes: Value('notas de $id'),
              ),
            );
        // El espejo primero: desde v18 las formas cuelgan de `item`.
        await db
            .into(db.knowledgeEntries)
            .insert(
              KnowledgeEntriesCompanion.insert(
                id: id,
                title: 'Fuente $id',
                kind: ItemKind.source,
                state: ItemState.processed,
                createdAt: now,
                updatedAt: now,
                deviceId: 'test',
              ),
            );
        await db
            .into(db.knowledgeSources)
            .insert(
              KnowledgeSourcesCompanion.insert(
                itemId: id,
                sourceType: SourceKind.webPage,
                capturedAt: now,
                contentHash: '',
                processingStatus: SourceProcessingStatus.done,
              ),
            );
        await db
            .into(db.renditions)
            .insert(
              RenditionsCompanion.insert(
                id: 'r-$id',
                itemId: id,
                kind: RenditionKind.markdown,
                isPrimary: true,
                createdAt: now,
                content: Value(text),
              ),
            );
      }
    }

    test('el dry-run cuenta lo que hará y no escribe nada', () async {
      await seedUnchunked();

      final plan = await planChunkBackfill(db);

      expect(plan.toChunk, ['a', 'b']);
      expect(plan.notesToCopy, 2);
      expect(plan.hasWork, isTrue);
      expect(await db.select(db.chunks).get(), isEmpty);
      final entry = await (db.select(
        db.knowledgeEntries,
      )..where((e) => e.id.equals('a'))).getSingle();
      expect(entry.notes, isNull);
    });

    test('aplicarlo fragmenta, copia y una segunda corrida ya no encuentra '
        'nada', () async {
      await seedUnchunked();
      final ids = FakeIdGenerator(prefix: 'ch');

      final first = await backfillChunksAndNotes(
        db,
        ids: ids,
        logger: _SilentLogger(),
      );
      final chunksAfterFirst = await db.select(db.chunks).get();
      final second = await backfillChunksAndNotes(
        db,
        ids: ids,
        logger: _SilentLogger(),
      );

      expect(first.toChunk, ['a', 'b']);
      expect(chunksAfterFirst, isNotEmpty);
      expect(second.hasWork, isFalse);
      expect(
        await db.select(db.chunks).get(),
        hasLength(chunksAfterFirst.length),
      );
      final report = await verifyChunkInvariant(db);
      expect(report.holds, isTrue, reason: report.violations.join('\n'));
    });
  });
}
