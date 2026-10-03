import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_relate_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/relation_confidence.dart';
import 'package:sinapsis/features/graph/domain/services/relation_suggestion_service.dart';
import 'package:sinapsis/features/relations/data/services/chunk_embedding_indexer_impl.dart';
import 'package:sinapsis/features/relations/data/services/relation_candidate_selector_impl.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/fake_embedding_service.dart';
import '../../../../support/fake_relation_suggestion_service.dart';

/// Un vector por palabra clave del texto: así cada prueba decide qué tan
/// parecido es cada elemento al que se organiza (el coseno con `SEMILLA`).
List<double> _vectorFor(String text) {
  if (text.contains('SEMILLA')) return [1, 0];
  if (text.contains('CERCA')) return [0.9, 0.4359]; // coseno 0,9
  if (text.contains('TIBIO')) return [0.7, 0.7141]; // coseno 0,7
  return [0, 1]; // coseno 0: ni llega a candidato
}

void main() {
  late AiOrganizeHarness vault;
  late FakeRelationSuggestionService model;
  late ChunkEmbeddingIndexerImpl indexer;
  late AutoRelateStep step;

  setUp(() {
    vault = AiOrganizeHarness();
    model = FakeRelationSuggestionService();
    final embeddings = FakeEmbeddingService(vectorFor: _vectorFor);
    indexer = ChunkEmbeddingIndexerImpl(
      database: vault.db,
      embeddings: embeddings,
      clock: vault.clock,
    );
    step = AutoRelateStep(
      database: vault.db,
      ids: vault.ids,
      embeddings: embeddings,
      indexer: indexer,
      selector: RelationCandidateSelectorImpl(database: vault.db),
      service: model,
      organize: vault.organize,
      suggestions: vault.suggestions,
      runs: vault.runs,
    );
  });

  tearDown(() => vault.close());

  /// Una fuente ya indexada, como queda después de su propia pasada.
  Future<void> indexed(String id, String content) async {
    await vault.source(id, title: 'Fuente $id', content: content);
    await indexer.indexItem(id);
  }

  RelationSuggestion said(
    String itemId,
    RelationKind kind,
    AiCertainty? certainty,
  ) => RelationSuggestion(
    itemId: itemId,
    kind: kind,
    reason: 'Motivo de $itemId',
    certainty: certainty,
  );

  test('lo seguro se crea marcado como de la IA y lo dudoso queda para '
      'revisar', () async {
    final seed = await vault.source(
      's',
      title: 'El Senado',
      content: 'SEMILLA: el Senado romano.',
    );
    await indexed('a', 'CERCA: las leyes del Senado.');
    await indexed('b', 'TIBIO: la república.');
    await indexed('c', 'Recetas de cocina.');
    model.suggestions = [
      said('a', RelationKind.relatedTo, AiCertainty.high),
      said('b', RelationKind.cites, AiCertainty.medium),
    ];
    final run = await vault.startRun('s');

    final report = await step.organize(seed, runId: run);

    expect(report, const AiStepReport(applied: 1, forReview: 1));
    // Lo lejano ni llega al modelo.
    expect(model.candidateIdsSent.single, ['a', 'b']);

    final relation = await vault.db.select(vault.db.relations).getSingle();
    expect(relation.fromItemId, 's');
    expect(relation.toItemId, 'a');
    expect(relation.kind, RelationKind.relatedTo);
    expect(relation.note, 'Motivo de a');
    expect(relation.origin, ContentOrigin.ai);
    expect(relation.aiRunId, run);
    expect(
      relation.confidence,
      closeTo(
        relationConfidence(cosine: 0.9, certainty: AiCertainty.high),
        1e-3,
      ),
    );

    final pending = await vault.suggestions.watchPendingSuggestions('s').first;
    final review = pending.single as RelationSuggestionEntry;
    expect(review.relatedItemId, 'b');
    expect(review.kind, RelationKind.cites);
    expect(review.reason, 'Motivo de b');
    expect(review.confidence, isNotNull);
  });

  test('no repite lo vinculado, lo propuesto, lo deshecho ni lo que «no '
      'era»', () async {
    final seed = await vault.source(
      's',
      title: 'El Senado',
      content: 'SEMILLA: el Senado romano.',
    );
    // Ya vinculado, por la persona y en el otro sentido.
    await indexed('linked', 'CERCA: uno.');
    await vault.organize.createRelation(
      fromItemId: 'linked',
      toItemId: 's',
      kind: RelationKind.cites,
    );
    // Ya propuesto desde el otro elemento, y descartado en «Para revisar».
    await indexed('proposed', 'CERCA: dos.');
    final proposal = (await vault.suggestions.createRelationSuggestion(
      targetItemId: 'proposed',
      relatedItemId: 's',
      relatedItemTitle: 'El Senado',
      kind: RelationKind.relatedTo,
      reason: 'x',
    )).getOrElse((f) => fail('$f'));
    await vault.suggestions.reject(proposal.id);
    // Un elemento cuya pasada de la IA se deshizo.
    await indexed('undone', 'CERCA: tres.');
    await vault.runs.undoRun(await vault.startRun('undone'));
    // Un vínculo que la persona dijo que «no era».
    await indexed('rejected', 'CERCA: cuatro.');
    final earlier = await vault.startRun('s');
    await vault.organize.createRelation(
      fromItemId: 's',
      toItemId: 'rejected',
      kind: RelationKind.relatedTo,
      ai: AiProvenance(runId: earlier),
    );
    final wrong = await vault.db.select(vault.db.relations).get();
    await vault.organize.rejectAiRelation(
      wrong.singleWhere((r) => r.toItemId == 'rejected').id,
    );
    model.suggestions = [
      said('rejected', RelationKind.relatedTo, AiCertainty.high),
    ];

    final report = await step.organize(seed, runId: await vault.startRun('s'));

    // «No era» es de ese tipo: el elemento llega al modelo, pero lo que
    // propone no se vuelve a crear.
    expect(model.candidateIdsSent.single, ['rejected']);
    expect(report, AiStepReport.nothing);
    final relations = await vault.db.select(vault.db.relations).get();
    expect(relations.map((r) => r.fromItemId), ['linked']);
    expect(
      (await vault.suggestions.suggestionsFor(
        's',
      )).getOrElse((f) => fail('$f')),
      isEmpty,
    );
  });

  test('una nota se vincula con vectores calculados en el momento', () async {
    await indexed('a', 'CERCA: las leyes del Senado.');
    final note = await vault.note(
      'n',
      title: 'Mi nota',
      content: 'SEMILLA: lo que pienso del Senado.',
    );
    model.suggestions = [said('a', RelationKind.relatedTo, AiCertainty.high)];

    final report = await step.organize(note, runId: await vault.startRun('n'));

    expect(report.applied, 1);
    final relation = await vault.db.select(vault.db.relations).getSingle();
    expect((relation.fromItemId, relation.toItemId), ('n', 'a'));
    // Las notas no se fragmentan: sus vectores no quedan guardados.
    expect(await vault.db.select(vault.db.chunks).get(), hasLength(1));
  });

  test('si el modelo repite un candidato, vale la primera vez', () async {
    final seed = await vault.source(
      's',
      title: 'El Senado',
      content: 'SEMILLA: el Senado romano.',
    );
    await indexed('a', 'CERCA: las leyes del Senado.');
    model.suggestions = [
      said('a', RelationKind.relatedTo, AiCertainty.high),
      said('a', RelationKind.contradicts, AiCertainty.high),
    ];

    final report = await step.organize(seed, runId: await vault.startRun('s'));

    expect(report.applied, 1);
    final relation = await vault.db.select(vault.db.relations).getSingle();
    expect(relation.kind, RelationKind.relatedTo);
  });

  test('sin candidatos no le pregunta nada al modelo', () async {
    final seed = await vault.source(
      's',
      title: 'El Senado',
      content: 'SEMILLA: el Senado romano.',
    );
    await indexed('c', 'Recetas de cocina.');

    expect(
      await step.organize(seed, runId: await vault.startRun('s')),
      AiStepReport.nothing,
    );
    expect(model.requests, isEmpty);
  });
}
