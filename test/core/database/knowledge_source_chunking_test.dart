import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
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

  test('chunking exitoso puebla fullText/contentHash y los chunks', () async {
    final item = await seedItem(
      renditions: [
        Rendition.text(
          id: 'rend-0',
          itemId: 'item-0',
          kind: RenditionKind.plainText,
          content: 'Primer párrafo.\n\nSegundo párrafo.',
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );

    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);

    expect(outcome, SourceChunkingOutcome.populated);
    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(source.fullText, 'Primer párrafo.\n\nSegundo párrafo.');
    expect(source.contentHash, isNotEmpty);

    final chunks =
        await (db.select(db.chunks)
              ..where((c) => c.itemId.equals(item.id))
              ..orderBy([(c) => OrderingTerm(expression: c.seq)]))
            .get();
    expect(chunks, hasLength(2));
    expect(chunks[0].content, 'Primer párrafo.\n\n');
    expect(chunks[1].content, 'Segundo párrafo.');
  });

  test('contentHash ya poblado: no duplica nada (idempotencia)', () async {
    final item = await seedItem(
      renditions: [
        Rendition.text(
          id: 'rend-0',
          itemId: 'item-0',
          kind: RenditionKind.plainText,
          content: 'Texto original.',
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    await chunkAndPersistSource(db, itemId: item.id, ids: ids);
    final chunksBefore = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();

    final outcome = await chunkAndPersistSource(db, itemId: item.id, ids: ids);

    expect(outcome, SourceChunkingOutcome.alreadyDone);
    final chunksAfter = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunksAfter, hasLength(chunksBefore.length));
  });

  test(
    'el chunking falla: se reporta en MigrationIssues, sin persistir nada',
    () async {
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

      final outcome = await chunkAndPersistSource(
        db,
        itemId: item.id,
        ids: ids,
      );

      expect(outcome, SourceChunkingOutcome.failed);
      final source = await (db.select(
        db.knowledgeSources,
      )..where((s) => s.itemId.equals(item.id))).getSingle();
      expect(source.contentHash, isEmpty);
      final chunks = await (db.select(
        db.chunks,
      )..where((c) => c.itemId.equals(item.id))).get();
      expect(chunks, isEmpty);

      final issues = await (db.select(
        db.migrationIssues,
      )..where((i) => i.itemId.equals(item.id))).get();
      expect(issues, hasLength(1));
      expect(issues.single.migration, 'f5_relation_engine');
      expect(issues.single.stage, 'chunk');
    },
  );
}
