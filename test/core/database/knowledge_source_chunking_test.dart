import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';

import '../../support/fake_id_generator.dart';
import '../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, sembrando fuentes por el mismo
/// camino que la app (`LibraryRepositoryImpl.save`, que ya mantiene el
/// espejo `item`/`source` sincronizado desde F3) — así el `contentHash`
/// vacío y la rendition de texto quedan en el mismo estado real que
/// tendría un elemento recién capturado.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late FakeIdGenerator ids;

  final now = DateTime(2026, 9, 18, 10);
  var counter = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ids = FakeIdGenerator();
    libraryRepository = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedItem({
    List<Rendition> renditions = const [],
  }) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: 'Un elemento',
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: renditions,
    );

    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  test('sin ninguna rendition de texto, no hace nada', () async {
    final item = await seedItem();

    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);

    expect(outcome, SourceChunkingOutcome.noTextYet);
    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(source.contentHash, isEmpty);
    final chunks = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunks, isEmpty);
  });

  Rendition textRendition(String text, {String id = 'rend-0'}) =>
      Rendition.text(
        id: id,
        itemId: 'item-0',
        kind: RenditionKind.plainText,
        content: text,
        isPrimary: true,
        createdAt: now,
      );

  Future<List<ChunkRow>> chunksOf(String itemId) =>
      (db.select(db.chunks)
            ..where((c) => c.itemId.equals(itemId))
            ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
          .get();

  test('guardar una fuente con texto la fragmenta: no hace falta pedirlo '
      'aparte', () async {
    final item = await seedItem(
      renditions: [textRendition('Primer párrafo.\n\nSegundo párrafo.')],
    );

    final chunks = await chunksOf(item.id);
    expect(chunks, hasLength(2));
    expect(chunks[0].content, 'Primer párrafo.\n\n');
    expect(chunks[1].content, 'Segundo párrafo.');

    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(source.contentHash, isNotEmpty);

    // Y pedirlo de nuevo no cambia nada.
    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);
    expect(outcome, SourceChunkingOutcome.alreadyDone);
  });

  test('pedirlo antes de que save() lo haga se fragmenta igual, con el mismo '
      'resultado', () async {
    final item = await seedItem();
    // Un texto que llega después, sin pasar por save(): lo que hace el
    // procesamiento en segundo plano por otros caminos.
    await db
        .into(db.renditions)
        .insert(
          RenditionsCompanion.insert(
            id: 'rend-tarde',
            itemId: item.id,
            kind: RenditionKind.plainText,
            isPrimary: true,
            createdAt: now,
            content: const Value('Uno.\n\nDos.'),
          ),
        );

    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);

    expect(outcome, SourceChunkingOutcome.populated);
    expect((await chunksOf(item.id)).map((c) => c.content), [
      'Uno.\n\n',
      'Dos.',
    ]);
  });

  test(
    'guardar de nuevo con el mismo texto no toca los chunks: mismos ids',
    () async {
      final item = await seedItem(
        renditions: [textRendition('Texto original.\n\nOtro párrafo.')],
      );
      final before = (await chunksOf(item.id)).map((c) => c.id).toList();

      await libraryRepository.save(item.copyWith(title: 'Otro título'));

      expect((await chunksOf(item.id)).map((c) => c.id), before);
    },
  );

  test('si el texto cambia, los chunks se rehacen, y los embeddings de los '
      'viejos se van con ellos', () async {
    final item = await seedItem(
      renditions: [textRendition('Texto original.\n\nOtro párrafo.')],
    );
    final old = await chunksOf(item.id);
    await db
        .into(db.embeddings)
        .insert(
          EmbeddingsCompanion.insert(
            chunkId: old.first.id,
            vector: Uint8List.fromList([1, 2, 3, 4]),
            modelVersion: 'm',
            createdAt: now,
          ),
        );

    await libraryRepository.save(
      item.copyWith(
        renditions: [textRendition('Un texto distinto por completo.')],
      ),
    );

    final rebuilt = await chunksOf(item.id);
    expect(rebuilt.map((c) => c.content), ['Un texto distinto por completo.']);
    expect(rebuilt.map((c) => c.id), isNot(contains(old.first.id)));
    expect(await db.select(db.embeddings).get(), isEmpty);
    // Y sigue reconstruyendo el texto de la forma principal.
    final report = await verifyChunkInvariant(db);
    expect(report.holds, isTrue, reason: report.violations.join('\n'));
  });

  group('número de página', () {
    const pdfText = 'uno\n\n---\n\n\n\n---\n\ntres';

    Future<KnowledgeItem> saveDocument(String? path, {String? id}) async {
      final n = counter++;
      final item = KnowledgeItem(
        id: 'doc-$n',
        title: 'Un documento',
        source: Source(
          id: 'src-doc-$n',
          kind: SourceKind.document,
          capturedAt: now,
          originalFilePath: path,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-doc-$n',
            itemId: 'doc-$n',
            kind: RenditionKind.markdown,
            content: pdfText,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );
      return (await libraryRepository.save(item)).getRight().toNullable()!;
    }

    test(
      'un PDF guardado numera sus chunks, y la página en blanco cuenta',
      () async {
        final item = await saveDocument('archivos/informe.pdf');

        final chunks = await chunksOf(item.id);

        expect(chunks.map((c) => c.content.trim()), [
          'uno',
          '---',
          '---',
          'tres',
        ]);
        expect(chunks.map((c) => c.pageNumber), [1, 1, 2, 3]);
      },
    );

    test(
      'lo que no es un PDF no se numera, aunque tenga separadores',
      () async {
        final item = await saveDocument('archivos/libro.epub');

        expect(
          (await chunksOf(item.id)).map((c) => c.pageNumber),
          everyElement(isNull),
        );
      },
    );

    test('las migraciones no numeran: un PDF de antes puede no traer sus '
        'páginas en blanco', () async {
      final item = await saveDocument('archivos/viejo.pdf');
      await (db.delete(db.chunks)..where((c) => c.itemId.equals(item.id))).go();
      await (db.update(db.knowledgeSources)
            ..where((s) => s.itemId.equals(item.id)))
          .write(const KnowledgeSourcesCompanion(contentHash: Value('')));

      // Sin `assignPages`, como lo llaman los backfills.
      await chunkAndPersistSource(db, itemId: item.id, ids: ids);

      final chunks = await chunksOf(item.id);
      expect(chunks, isNotEmpty);
      expect(chunks.map((c) => c.pageNumber), everyElement(isNull));
    });
  });

  test('una nota no se fragmenta', () async {
    final result = await libraryRepository.save(
      KnowledgeItem(
        id: 'nota',
        title: 'Una nota',
        source: Source(
          id: 'src-nota',
          kind: SourceKind.manualNote,
          capturedAt: now,
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-nota',
            itemId: 'nota',
            kind: RenditionKind.blocks,
            content: encodeContentBlocks([
              const ContentBlock.paragraph(text: 'Algo que pensé.'),
            ]),
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );

    expect(result.isRight(), isTrue);
    expect(await db.select(db.chunks).get(), isEmpty);
  });

  test('el chunking falla: se reporta en MigrationIssues, el guardado sigue y '
      'no se persiste ningún chunk', () async {
    final item = await seedItem(
      renditions: [
        Rendition.text(
          id: 'rend-0',
          itemId: 'item-0',
          kind: RenditionKind.blocks,
          content: 'esto no es JSON válido',
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );

    // El guardado NO se cayó: la fuente está, con su texto.
    final found = (await libraryRepository.findById(
      item.id,
    )).getRight().toNullable();
    expect(found, isNotNull);
    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(source.contentHash, isEmpty);
    expect(await chunksOf(item.id), isEmpty);
    final issues = await (db.select(
      db.migrationIssues,
    )..where((i) => i.itemId.equals(item.id))).get();
    expect(issues, hasLength(1));
    expect(issues.single.migration, 'f10_save');
    expect(issues.single.stage, 'chunk');

    // Pedirlo por otro camino falla igual, y lo informa con su propio nombre.
    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);
    expect(outcome, SourceChunkingOutcome.failed);
    final all = await db.select(db.migrationIssues).get();
    expect(all.map((i) => i.migration), ['f10_save', 'f5_relation_engine']);
  });
}
