import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/usecases/backfill_embeddings_usecase_impl.dart';
import 'package:sinapsis/features/relations/domain/services/chunk_embedding_indexer.dart';

import '../../../../support/fake_embedding_service.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con `ChunkEmbeddingIndexerImpl` real
/// sobre un `FakeEmbeddingService` —mismo patrón que
/// `chunk_embedding_indexer_impl_test.dart`, un nivel más arriba: acá lo
/// que se prueba es que el recorrido de fuentes y el reporte de progreso
/// sean correctos, no el indexado en sí.
void main() {
  late AppDatabase db;

  final now = DateTime(2026, 9, 18, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String> seedItemWithChunks(String itemId, {int chunkCount = 1}) async {
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: 'Elemento $itemId',
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    for (var i = 0; i < chunkCount; i++) {
      await db
          .into(db.chunks)
          .insert(
            ChunksCompanion.insert(
              id: '$itemId-chunk-$i',
              itemId: itemId,
              seq: i,
              content: 'Contenido de $itemId, fragmento $i',
              charStart: i * 10,
              charEnd: (i + 1) * 10,
            ),
          );
    }
    return itemId;
  }

  BackfillEmbeddingsUseCaseImpl build(ChunkEmbeddingIndexer indexer) {
    return BackfillEmbeddingsUseCaseImpl(
      database: db,
      indexer: indexer,
      telemetry: MockTelemetryService(),
    );
  }

  test('sin ninguna fuente con chunks, no emite nada', () async {
    final indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: FakeEmbeddingService(),
      clock: () => now,
    );

    final progress = await build(indexer).call().toList();

    expect(progress, isEmpty);
  });

  test('el progreso avanza de a uno, con el total correcto', () async {
    await seedItemWithChunks('item-1');
    await seedItemWithChunks('item-2');
    await seedItemWithChunks('item-3');
    final indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: FakeEmbeddingService(),
      clock: () => now,
    );

    final progress = await build(indexer).call().toList();

    expect(progress, hasLength(3));
    expect(progress.map((p) => p.processedItems), [1, 2, 3]);
    expect(progress.every((p) => p.totalItems == 3), isTrue);
    expect(progress.last.indexedChunks, 3);
  });

  test('un ítem que falla no corta el resto', () async {
    await seedItemWithChunks('item-ok-1');
    await seedItemWithChunks('item-falla');
    await seedItemWithChunks('item-ok-2');
    final indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: FakeEmbeddingService(
        vectorFor: (text) {
          if (text.contains('item-falla')) {
            // El indexador no le pide nada especial al tipo de error de
            // un embed que falla, mismo criterio que
            // `FakeEmbeddingService.error`.
            // ignore: only_throw_errors
            throw Exception('el modelo explotó');
          }
          return [text.length.toDouble(), 0, 0];
        },
      ),
      clock: () => now,
    );

    final progress = await build(indexer).call().toList();

    expect(progress, hasLength(3));
    // Los dos ítems que sí funcionan se indexan igual — el que falla no
    // suma nada, pero tampoco corta el recorrido de los otros dos.
    expect(progress.last.indexedChunks, 2);
  });

  test('correrlo dos veces: la segunda no reindexa nada', () async {
    await seedItemWithChunks('item-1');
    await seedItemWithChunks('item-2');
    final indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: FakeEmbeddingService(),
      clock: () => now,
    );
    final usecase = build(indexer);
    await usecase.call().toList();

    final secondRun = await usecase.call().toList();

    expect(secondRun.last.indexedChunks, 0);
  });
}
