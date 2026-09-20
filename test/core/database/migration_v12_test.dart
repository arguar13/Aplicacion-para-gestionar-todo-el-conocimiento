import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/migrations/backfill_source_chunks_v12.dart';
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

/// `backfillSourceChunks` —el catch-up de `schemaVersion` 11→12—
/// probada como función pura contra una base ya en `schemaVersion` 12,
/// sembrando fuentes por el mismo camino que la app
/// (`LibraryRepositoryImpl.save`) para que el espejo `source` quede en
/// el mismo estado real que tendría una bóveda existente: mismo
/// criterio que `knowledge_source_chunking_test.dart` y que el resto de
/// las migraciones de backfill del proyecto.
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

  test('puebla las fuentes con contentHash vacío', () async {
    final item = await seedItem(
      renditions: [
        Rendition.text(
          id: 'rend-0',
          itemId: 'item-0',
          kind: RenditionKind.plainText,
          content: 'Texto de la fuente.',
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );

    await backfillSourceChunks(db, ids: ids);

    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    // F10: el texto no se copia a `source`; lo que queda es su hash y los
    // chunks, que lo reconstruyen.
    expect(source.fullText, isEmpty);
    expect(source.contentHash, isNotEmpty);
    final chunks = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunks, isNotEmpty);
  });

  test('no toca una fuente que ya tiene contentHash poblado', () async {
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
    await backfillSourceChunks(db, ids: ids);
    final chunksBefore = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();

    await backfillSourceChunks(db, ids: ids);

    final chunksAfter = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunksAfter, hasLength(chunksBefore.length));
  });

  test('una fuente sin ninguna rendition de texto queda intacta', () async {
    final item = await seedItem();

    await backfillSourceChunks(db, ids: ids);

    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals(item.id))).getSingle();
    expect(source.contentHash, isEmpty);
    final chunks = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunks, isEmpty);
  });
}
