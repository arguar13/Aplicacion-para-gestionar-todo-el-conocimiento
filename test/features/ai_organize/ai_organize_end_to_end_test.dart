import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_organize_backlog_impl.dart';
import 'package:sinapsis/features/ai_organize/data/services/vocabulary_candidates.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_flashcards_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_properties_step.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_relate_step.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart';
import 'package:sinapsis/features/ai_organize/domain/services/charging_probe.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';
import 'package:sinapsis/features/transform/data/repositories/processing_state_repository_impl.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer_registry.dart';
import 'package:sinapsis/features/transform/domain/usecases/process_item_usecase.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue.dart';

import '../../support/ai_organize_harness.dart';
import '../../support/fake_chat_model_manager.dart';
import '../../support/fake_duplicate_suggestion_generator.dart';
import '../../support/fake_embedding_model_manager.dart';
import '../../support/fake_embedding_service.dart';
import '../../support/fake_metadata_suggestion_generator.dart';
import '../../support/fake_property_suggestion_service.dart';
import '../../support/fake_relation_suggestion_service.dart';
import '../../support/silent_logger.dart';
import '../../support/transform_test_doubles.dart';

class _NeverCharging implements ChargingProbe {
  @override
  Future<bool> isCharging() async => false;

  @override
  Stream<bool> watchCharging() => const Stream.empty();
}

/// Una tarjeta por pedido, anclada a la única frase que trae el
/// transformador falso.
class _OneCard implements FlashcardGenerator {
  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async => const [
    FlashcardDraft(
      front: '¿Qué se trajo?',
      back: 'El contenido.',
      quote: 'El contenido que se trajo.',
    ),
  ];
}

/// De punta a punta (F27): un elemento termina de procesarse, la cola de la
/// IA lo toma sola, la pasada crea vínculos, tarjetas y propiedades marcadas
/// como de la IA, y deshacerla se lleva todo. Lo único falso son los modelos
/// y la red.
void main() {
  late AiOrganizeHarness vault;
  late String epoca;

  setUp(() async {
    vault = AiOrganizeHarness();
    epoca = (await vault.organize.getOrCreatePropertyDefinition(
      'Época',
    )).getOrElse((f) => fail('$f')).id;
  });

  tearDown(() => vault.close());

  test('procesar un elemento → la IA lo organiza sola → deshacer la pasada '
      'se lleva todo', () async {
    final embeddings = FakeEmbeddingService(
      vectorFor: (text) => text.contains('Senado') ? [0.9, 0.4359] : [1.0, 0.0],
    );
    final indexer = ChunkEmbeddingIndexerImpl(
      database: vault.db,
      embeddings: embeddings,
      clock: vault.clock,
    );
    // Lo que ya había en la biblioteca, de antes de que la IA organizara
    // sola: indexado y con su época puesta a mano.
    await vault.source(
      'senado',
      title: 'El Senado',
      content: 'El Senado romano.',
      createdAt: DateTime(2026, 9),
    );
    await indexer.indexItem('senado');
    await vault.organize.assignProperty(
      itemId: 'senado',
      definitionId: epoca,
      value: 'Antigua',
    );
    // Lo nuevo, capturado y esperando a procesarse.
    await vault.library.save(
      KnowledgeItem(
        id: 'nuevo',
        title: 'Provisorio',
        source: Source(
          id: 'src-nuevo',
          kind: SourceKind.webPage,
          capturedAt: vault.now,
          url: 'https://ejemplo.org/nuevo',
        ),
        processingState: ProcessingState.pending,
        createdAt: vault.now,
        updatedAt: vault.now,
      ),
    );

    final ai = AiOrganizeQueue(
      backlog: AiOrganizeBacklogImpl(vault.db),
      runs: vault.runs,
      library: vault.library,
      steps: () => [
        AutoPropertiesStep(
          vocabulary: VocabularyCandidatesReader(
            database: vault.db,
            embeddings: embeddings,
            clock: vault.clock,
          ),
          service: FakePropertySuggestionService(
            drafts: [
              PropertyDraft(
                definitionId: epoca,
                definitionName: 'Época',
                value: 'Antigua',
              ),
            ],
          ),
          organize: vault.organize,
          suggestions: vault.suggestions,
          runs: vault.runs,
        ),
        AutoRelateStep(
          database: vault.db,
          ids: vault.ids,
          indexer: indexer,
          selector: RelationCandidateSelectorImpl(database: vault.db),
          service: FakeRelationSuggestionService(
            suggestions: const [
              RelationSuggestion(
                itemId: 'senado',
                kind: RelationKind.relatedTo,
                reason: 'Los dos hablan del Senado',
                certainty: AiCertainty.high,
              ),
            ],
          ),
          organize: vault.organize,
          suggestions: vault.suggestions,
          runs: vault.runs,
        ),
        AutoFlashcardsStep(
          generator: _OneCard(),
          flashcards: vault.flashcards,
          suggestions: vault.suggestions,
          runs: vault.runs,
        ),
      ],
      chatModel: () => FakeChatModelManager(ready: true),
      embeddingModel: () => FakeEmbeddingModelManager(ready: true),
      vectors: () => indexer,
      charging: _NeverCharging(),
      epoch: () async => DateTime(2026, 10),
      telemetry: vault.telemetry,
      clock: vault.clock,
      onStatus: (_) {},
      settings: const AiOrganizeSettings(backfillWhileCharging: false),
    );
    addTearDown(ai.dispose);

    final processed = Completer<void>();
    final processing = ProcessingQueueNotifier(
      processItem: () => ProcessItemUseCase(
        registry: TransformerRegistry([FakeTransformer()]),
        repository: vault.library,
        processingStates: ProcessingStateRepositoryImpl(vault.db),
        logger: const SilentLogger(),
        telemetry: vault.telemetry,
        clock: vault.clock,
        duplicateSuggestionGenerator: FakeDuplicateSuggestionGenerator(),
        metadataSuggestionGenerator: FakeMetadataSuggestionGenerator(),
      ),
      processingStates: () => ProcessingStateRepositoryImpl(vault.db),
      logger: const SilentLogger(),
      onProcessed: (item) {
        ai.itemProcessed(item.id);
        processed.complete();
      },
    );
    addTearDown(processing.dispose);

    processing.enqueue('nuevo');
    await processed.future;
    await ai.settled;

    // La pasada: lo que creó, todo marcado como de la IA.
    final run = (await vault.runs.listRuns(
      itemId: 'nuevo',
    )).getOrElse((f) => fail('$f')).single;
    expect(
      run.created,
      const AiRunTally(relations: 1, flashcards: 1, properties: 1),
    );
    final relation = await vault.db.select(vault.db.relations).getSingle();
    expect((relation.fromItemId, relation.toItemId), ('nuevo', 'senado'));
    expect((relation.origin, relation.aiRunId), (ContentOrigin.ai, run.id));
    expect(relation.note, 'Los dos hablan del Senado');
    final card = await vault.db.select(vault.db.flashcards).getSingle();
    expect((card.origin, card.aiRunId), (ContentOrigin.ai, run.id));
    final property = (await vault.reload('nuevo')).properties.single;
    expect(
      (property.value, property.origin),
      ('Antigua', ItemPropertyOrigin.ai),
    );

    // Deshacer la pasada se lleva todo lo de la IA, y nada de la persona.
    final undone = (await vault.runs.undoRun(
      run.id,
    )).getOrElse((f) => fail('$f'));
    expect(undone, run.created);
    expect(await vault.db.select(vault.db.relations).get(), isEmpty);
    expect(await vault.db.select(vault.db.flashcards).get(), isEmpty);
    expect((await vault.reload('nuevo')).properties, isEmpty);
    expect((await vault.reload('senado')).properties.single.value, 'Antigua');

    // Y la IA no lo vuelve a organizar sola.
    await ai.wake();
    expect(
      (await vault.runs.listRuns(itemId: 'nuevo')).getOrElse((f) => fail('$f')),
      hasLength(1),
    );
  });
}
