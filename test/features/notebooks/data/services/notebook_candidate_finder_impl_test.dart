import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/data/services/chunk_passage_retriever.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/notebooks/data/services/notebook_candidate_finder_impl.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_candidates.dart';
import 'package:sinapsis/features/relations/data/services/item_vector_index_impl.dart';

import '../../../../support/fake_embedding_service.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: el índice de texto de verdad y vectores de
/// juguete de tres dimensiones (F30).
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late FakeEmbeddingService embeddings;
  late MockTelemetryService telemetry;
  var embeddingsReady = true;
  final now = DateTime(2026, 10, 4, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      files: InMemoryFileStore(),
    );
    // Lo que se busca apunta a la primera dimensión.
    embeddings = FakeEmbeddingService(vectorFor: (_) => const [1, 0, 0]);
    telemetry = MockTelemetryService();
    embeddingsReady = true;
  });

  tearDown(() => db.close());

  NotebookCandidateFinderImpl finder() => NotebookCandidateFinderImpl(
    database: db,
    retriever: ChunkPassageRetriever(database: db),
    vectors: ItemVectorIndexImpl(database: db),
    embeddings: embeddings,
    embeddingsReady: () async => embeddingsReady,
    telemetry: telemetry,
  );

  /// Una fuente con su texto y, si se da, el mismo vector en cada fragmento.
  Future<void> seed(
    String id,
    String title,
    String content, {
    List<double>? vector,
  }) async {
    await library.save(
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://ejemplo.org/$id',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-$id',
            itemId: id,
            kind: RenditionKind.plainText,
            content: content,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      ),
    );
    if (vector == null) return;
    final chunks = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(id))).get();
    for (final chunk in chunks) {
      await db
          .into(db.embeddings)
          .insert(
            EmbeddingsCompanion.insert(
              chunkId: chunk.id,
              vector: encodeEmbeddingVector(vector),
              modelVersion: 'test',
              createdAt: now,
            ),
          );
    }
  }

  test('junta lo que encuentran las palabras y el sentido, sin las palabras '
      'de para qué es el cuaderno', () async {
    await seed(
      'foro',
      'El foro romano',
      'El foro era el centro de la vida pública de Roma.',
    );
    await seed(
      'senado',
      'El Senado',
      'Trescientos miembros elegidos entre los patricios.',
      vector: const [0.9, 0.1, 0],
    );
    await seed(
      'tesis',
      'Cómo escribir una tesis',
      'Una tesis tiene introducción, desarrollo y conclusión.',
      vector: const [0, 0, 1],
    );

    final result = await finder().find('mi tesis sobre Roma');

    expect(result.senseSearch, SenseSearch.used);
    expect(embeddings.queryRequests, ['mi tesis sobre Roma']);
    final byId = {for (final c in result.candidates) c.itemId: c};
    expect(byId.keys, unorderedEquals(['foro', 'senado']));
    expect(byId['foro']!.matchedText, isTrue);
    expect(byId['foro']!.excerpt, contains('Roma'));
    expect(byId['senado']!.matchedText, isFalse);
    expect(byId['senado']!.similarity, greaterThan(kNotebookMinSimilarity));
    expect(byId['senado']!.excerpt, contains('Trescientos'));
    expect(byId['senado']!.kind, SourceKind.webPage);
  });

  test('sin el modelo de vínculos, solo por palabras, y lo dice', () async {
    embeddingsReady = false;
    await seed(
      'foro',
      'El foro romano',
      'El foro era el centro de Roma.',
      vector: const [1, 0, 0],
    );
    await seed(
      'senado',
      'El Senado',
      'Trescientos miembros.',
      vector: const [1, 0, 0],
    );

    final result = await finder().find('Roma');

    expect(result.senseSearch, SenseSearch.unavailable);
    expect(embeddings.queryRequests, isEmpty);
    expect(result.candidates.map((c) => c.itemId), ['foro']);
  });

  test('si buscar por sentido falla, sigue con las palabras, lo registra y '
      'lo dice', () async {
    embeddings.error = StateError('el modelo de vínculos falló');
    await seed('foro', 'El foro romano', 'El foro era el centro de Roma.');

    final result = await finder().find('Roma');

    expect(result.senseSearch, SenseSearch.failed);
    expect(result.candidates.map((c) => c.itemId), ['foro']);
    verify(
      () =>
          telemetry.recordError(any<Object>(), any(), hint: any(named: 'hint')),
    ).called(1);
  });

  test('nada que coincida, nada propuesto', () async {
    await seed('foro', 'El foro romano', 'El foro era el centro de Roma.');

    final result = await finder().find('fotosíntesis');

    expect(result.candidates, isEmpty);
  });
}
