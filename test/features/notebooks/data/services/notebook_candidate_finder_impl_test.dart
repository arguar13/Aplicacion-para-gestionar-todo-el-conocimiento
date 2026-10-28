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
import 'package:sinapsis/features/processed/data/repositories/processed_repository_impl.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/process_source_usecase.dart';
import 'package:sinapsis/features/relations/data/services/item_vector_index_impl.dart';

import '../../../../support/fake_embedding_service.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/item_rows.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria: el índice de texto de verdad y vectores de
/// juguete de tres dimensiones (F30). Lo que se propone son documentos
/// procesados (F41, paso 5): cada fuente se procesa pasándola sin modificar,
/// salvo las que se dejan a propósito solo en la Biblioteca.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl library;
  late ProcessedRepositoryImpl processed;
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
    processed = ProcessedRepositoryImpl(
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
    processed: processed,
    retriever: ChunkPassageRetriever(database: db),
    vectors: ItemVectorIndexImpl(database: db),
    embeddings: embeddings,
    embeddingsReady: () async => embeddingsReady,
    telemetry: telemetry,
  );

  /// El documento procesado de la fuente [sourceId].
  String doc(String sourceId) => processedDocumentIdFor(sourceId);

  /// Una fuente con su texto y, si se da, el mismo vector en cada fragmento;
  /// con [andProcess], pasada a Procesado sin modificar.
  Future<void> seed(
    String id,
    String title,
    String content, {
    List<double>? vector,
    bool andProcess = true,
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
    if (andProcess) {
      final result = await ProcessSourceUseCase(processed).passUnchanged(id);
      expect(result.isRight(), isTrue);
    }
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
      'de para qué es el cuaderno, y propone solo procesados', () async {
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
    // Habla de Roma y se parece, pero no se procesó: es de la Biblioteca.
    await seed(
      'circo',
      'El circo',
      'Las carreras de Roma.',
      vector: const [1, 0, 0],
      andProcess: false,
    );

    final result = await finder().find('mi tesis sobre Roma');

    expect(result.senseSearch, SenseSearch.used);
    expect(embeddings.queryRequests, ['mi tesis sobre Roma']);
    final byId = {for (final c in result.candidates) c.itemId: c};
    expect(byId.keys, unorderedEquals([doc('foro'), doc('senado')]));
    expect(byId[doc('foro')]!.matchedText, isTrue);
    expect(byId[doc('foro')]!.excerpt, contains('Roma'));
    expect(byId[doc('senado')]!.matchedText, isFalse);
    expect(
      byId[doc('senado')]!.similarity,
      greaterThan(kNotebookMinSimilarity),
    );
    // Lo que se muestra es el texto del procesado.
    expect(byId[doc('senado')]!.excerpt, contains('Trescientos'));
    expect(byId[doc('senado')]!.kind, SourceKind.webPage);
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
    expect(result.candidates.map((c) => c.itemId), [doc('foro')]);
  });

  test('si buscar por sentido falla, sigue con las palabras, lo registra y '
      'lo dice', () async {
    embeddings.error = StateError('el modelo de vínculos falló');
    await seed('foro', 'El foro romano', 'El foro era el centro de Roma.');

    final result = await finder().find('Roma');

    expect(result.senseSearch, SenseSearch.failed);
    expect(result.candidates.map((c) => c.itemId), [doc('foro')]);
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

  test('sin ningún procesado no propone nada, ni busca: las fuentes de la '
      'Biblioteca no van en un cuaderno', () async {
    await seed(
      'foro',
      'El foro romano',
      'El foro era el centro de Roma.',
      vector: const [1, 0, 0],
      andProcess: false,
    );

    final result = await finder().find('Roma');

    expect(result.candidates, isEmpty);
    expect(embeddings.queryRequests, isEmpty);
  });

  test('lo encontrado solo por el título muestra el principio de lo '
      'procesado', () async {
    await seed('foro', 'Roma', 'El foro era el centro de la vida pública.');

    final result = await finder().find('Roma');

    expect(result.candidates.single.itemId, doc('foro'));
    expect(result.candidates.single.excerpt, contains('El foro'));
  });

  test('lo procesado que está en la papelera no se propone', () async {
    await seed('foro', 'El foro romano', 'El foro era el centro de Roma.');
    await trashItemRows(db, doc('foro'));

    final result = await finder().find('Roma');

    expect(result.candidates, isEmpty);
  });

  test('lo que el sentido encuentra fuera de lo procesado vivo no le quita '
      'el lugar a otro', () async {
    await seed('foro', 'El foro', 'Plaza central.', vector: const [1, 0, 0]);
    await seed(
      'senado',
      'El Senado',
      'Trescientos miembros.',
      vector: const [0.9, 0.1, 0],
    );
    await trashItemRows(db, doc('foro'));

    final result = await finder().find('Roma', limit: 1);

    expect(result.candidates.map((c) => c.itemId), [doc('senado')]);
  });

  test('una fuente sin procesar más parecida no le quita el lugar a un '
      'procesado', () async {
    await seed(
      'circo',
      'El circo',
      'Carreras.',
      vector: const [1, 0, 0],
      andProcess: false,
    );
    await seed(
      'senado',
      'El Senado',
      'Trescientos miembros.',
      vector: const [0.9, 0.1, 0],
    );

    final result = await finder().find('Roma', limit: 1);

    expect(result.candidates.map((c) => c.itemId), [doc('senado')]);
  });

  test('por palabras busca solo en lo procesado: una fuente que coincide más '
      'no le quita el lugar', () async {
    await seed(
      'circo',
      'El circo de Roma',
      'Roma, Roma y más Roma.',
      andProcess: false,
    );
    await seed('foro', 'El foro', 'El foro era el centro de Roma.');

    final result = await finder().find('Roma', limit: 1);

    expect(result.candidates.map((c) => c.itemId), [doc('foro')]);
  });
}
