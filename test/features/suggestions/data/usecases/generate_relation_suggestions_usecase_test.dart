import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_source_chunking.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/duplicates/data/usecases/merge_duplicate_items_usecase_impl.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/organize/data/repositories/organize_repository_impl.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';
import 'package:sinapsis/features/suggestions/data/repositories/suggestion_repository_impl.dart';
import 'package:sinapsis/features/suggestions/data/usecases/generate_relation_suggestions_usecase.dart';

import '../../../../support/fake_chat_model_manager.dart';
import '../../../../support/fake_embedding_model_manager.dart';
import '../../../../support/fake_embedding_service.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/fake_relation_suggestion_service.dart';
import '../../../../support/in_memory_file_store.dart';

class MockTelemetryService extends Mock implements TelemetryService {}

/// Contra SQLite real, en memoria, con `LibraryRepositoryImpl`,
/// `OrganizeRepositoryImpl`, `ChunkEmbeddingIndexerImpl` y
/// `RelationCandidateSelectorImpl` reales: el chunking, la exclusión de ya
/// vinculados y la preselección por similitud dependen de datos de verdad,
/// no de un doble — solo se reemplazan los tres bordes que de verdad tocan
/// un modelo (`EmbeddingModelManager`, `ChatModelManager`,
/// `RelationSuggestionService`) y el propio `EmbeddingService`, que
/// `FakeEmbeddingService` deja determinístico (mismo vector, en la misma
/// dirección, para cualquier texto no vacío: cualquier par de elementos con
/// contenido sembrado queda con similitud coseno 1.0).
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl libraryRepository;
  late OrganizeRepositoryImpl organizeRepository;
  late SuggestionRepositoryImpl suggestionRepository;
  late FakeEmbeddingModelManager embeddingModelManager;
  late FakeChatModelManager chatModelManager;
  late FakeRelationSuggestionService service;
  late ChunkEmbeddingIndexerImpl indexer;
  late GenerateRelationSuggestionsUseCase generator;
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
    organizeRepository = OrganizeRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      ids: ids,
      clock: () => now,
    );
    suggestionRepository = SuggestionRepositoryImpl(
      database: db,
      telemetry: MockTelemetryService(),
      organize: organizeRepository,
      merge: MergeDuplicateItemsUseCaseImpl(
        database: db,
        library: libraryRepository,
        ids: ids,
        clock: () => now,
        telemetry: MockTelemetryService(),
      ),
      ids: ids,
      clock: () => now,
    );
    embeddingModelManager = FakeEmbeddingModelManager(ready: true);
    chatModelManager = FakeChatModelManager(ready: true);
    service = FakeRelationSuggestionService();
    indexer = ChunkEmbeddingIndexerImpl(
      database: db,
      embeddings: FakeEmbeddingService(),
      clock: () => now,
    );
    generator = GenerateRelationSuggestionsUseCase(
      database: db,
      ids: ids,
      embeddingModelManager: embeddingModelManager,
      indexer: indexer,
      selector: RelationCandidateSelectorImpl(database: db),
      chatModelManager: chatModelManager,
      service: service,
      organize: organizeRepository,
      suggestions: suggestionRepository,
      telemetry: MockTelemetryService(),
    );
    counter = 0;
  });

  tearDown(() => db.close());

  Future<KnowledgeItem> seedSource({
    String title = 'Un elemento',
    String content = 'Contenido sobre Roma antigua y su Senado.',
  }) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/$n',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
      renditions: [
        Rendition.text(
          id: 'rend-$n',
          itemId: 'item-$n',
          kind: RenditionKind.plainText,
          content: content,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  /// Un candidato ya chunkeado e indexado por su cuenta —simula que otro
  /// disparo anterior del motor (o el backfill de F5) ya lo dejó con
  /// embeddings propios—, que es lo que `RelationCandidateSelector`
  /// necesita para poder encontrarlo: `generator.generate()` solo
  /// chunkea/indexa el elemento semilla que se le pasa, nunca a los demás.
  Future<KnowledgeItem> seedIndexedCandidate({required String title}) async {
    final candidate = await seedSource(title: title);
    await chunkAndPersistSource(db, itemId: candidate.id, ids: ids);
    await indexer.indexItem(candidate.id);
    return candidate;
  }

  Future<KnowledgeItem> seedNote({String title = 'Una nota'}) async {
    final n = counter++;
    final item = KnowledgeItem(
      id: 'item-$n',
      title: title,
      source: Source(
        id: 'src-$n',
        kind: SourceKind.manualNote,
        capturedAt: now,
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    final result = await libraryRepository.save(item);
    return result.getRight().toNullable()!;
  }

  test('una nota no genera ninguna sugerencia', () async {
    final note = await seedNote();

    await generator.generate(note);

    expect(service.requests, isEmpty);
    final pending = await suggestionRepository
        .watchPendingSuggestions(note.id)
        .first;
    expect(pending, isEmpty);
  });

  test('una fuente sin el modelo de embeddings listo solo chunkea, '
      'no genera sugerencias', () async {
    embeddingModelManager.ready = false;
    final item = await seedSource();

    await generator.generate(item);

    final chunks = await (db.select(
      db.chunks,
    )..where((c) => c.itemId.equals(item.id))).get();
    expect(chunks, isNotEmpty);
    expect(service.requests, isEmpty);
    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, isEmpty);
  });

  test('con ambos modelos listos y un candidato similar, genera una '
      'sugerencia de relación con confidence correcto', () async {
    final item = await seedSource(title: 'Semilla');
    final candidate = await seedIndexedCandidate(title: 'Candidato');
    service.suggestions = [
      RelationSuggestion(
        itemId: candidate.id,
        kind: RelationKind.relatedTo,
        reason: 'Ambos hablan de Roma antigua.',
      ),
    ];

    await generator.generate(item);

    expect(service.requests, hasLength(1));
    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, hasLength(1));
    final suggestion = pending.single as RelationSuggestionEntry;
    expect(suggestion.relatedItemId, candidate.id);
    expect(suggestion.relatedItemTitle, candidate.title);
    expect(suggestion.kind, RelationKind.relatedTo);
    expect(suggestion.confidence, closeTo(1.0, 1e-9));
  });

  test('un candidato ya vinculado queda excluido', () async {
    final item = await seedSource(title: 'Semilla');
    final linked = await seedIndexedCandidate(title: 'Ya vinculado');
    final other = await seedIndexedCandidate(title: 'Sin vincular');
    await organizeRepository.createRelation(
      fromItemId: item.id,
      toItemId: linked.id,
      kind: RelationKind.relatedTo,
    );

    await generator.generate(item);

    expect(service.requests, hasLength(1));
    expect(service.requests.single.candidateCount, 1);
    expect(other, isNotNull);
  });

  test('si el servicio lanza, generate() no lo deja escapar', () async {
    final item = await seedSource(title: 'Semilla');
    await seedIndexedCandidate(title: 'Candidato');
    service.error = Exception('el modelo explotó');

    await expectLater(generator.generate(item), completes);

    final pending = await suggestionRepository
        .watchPendingSuggestions(item.id)
        .first;
    expect(pending, isEmpty);
  });
}
