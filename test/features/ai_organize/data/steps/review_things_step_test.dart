import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' show Either, Unit, right, unit;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/correction_subject.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/data/steps/review_things_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/things_reviewer.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/atlas_topics.dart';

/// Un revisor de mentira: contesta lo que diga [verdictFor] de cada cosa, y
/// anota cada tanda que le llega.
class _FakeReviewer implements ThingsReviewer {
  ThingVerdict? Function(int index, ThingToReview thing) verdictFor = (_, _) =>
      null;

  final calls =
      <({String title, String excerpt, List<ThingToReview> things})>[];

  @override
  Future<List<ThingVerdict>> reviewThings({
    required String itemTitle,
    required String itemExcerpt,
    required List<ThingToReview> things,
  }) async {
    calls.add((title: itemTitle, excerpt: itemExcerpt, things: things));
    return [
      for (final (index, thing) in things.indexed) ?verdictFor(index, thing),
    ];
  }
}

void main() {
  late AiOrganizeHarness vault;
  late _FakeReviewer reviewer;
  late AiAtlasRepositoryImpl atlas;
  late ReviewThingsStep step;
  late ModelTextBudget budget;
  late String tema;

  setUp(() async {
    vault = AiOrganizeHarness();
    reviewer = _FakeReviewer();
    budget = kSmallWindowTextBudget;
    atlas = AiAtlasRepositoryImpl(
      database: vault.db,
      library: vault.library,
      organize: vault.organize,
      runs: vault.runs,
      telemetry: vault.telemetry,
      ids: vault.ids,
      clock: vault.clock,
    );
    step = ReviewThingsStep(
      reviewer: reviewer,
      runs: vault.runs,
      atlas: atlas,
      suggestions: vault.suggestions,
      textBudget: () => budget,
    );
    await vault.source('a', title: 'Rayuela', content: 'Una novela larga.');
    await vault.source('b', title: 'Cortázar', content: 'Un escritor.');
    tema = await temaDefinitionId(vault.db);
    for (final (id, name) in [('lit', 'Literatura'), ('arte', 'Arte')]) {
      await vault.db
          .into(vault.db.spaces)
          .insert(
            SpacesCompanion.insert(id: id, name: name, createdAt: vault.now),
          );
    }
    ok(
      await vault.organize.assignProperty(
        itemId: 'b',
        definitionId: tema,
        value: 'Novela',
      ),
    );
  });

  tearDown(() => vault.close());

  /// Una pasada de [model] sobre «a» que hace de todo.
  Future<String> organizeA({String model = 'Gemma 4 E4B'}) async {
    final run = ok(await vault.runs.startRun('a', model: model));
    ok(
      await vault.organize.createRelation(
        fromItemId: 'a',
        toItemId: 'b',
        kind: RelationKind.relatedTo,
        note: 'El autor.',
        ai: AiProvenance(runId: run),
      ),
    );
    ok(
      await vault.organize.assignProperty(
        itemId: 'a',
        definitionId: tema,
        value: 'Cuento',
        origin: ItemPropertyOrigin.ai,
        aiRunId: run,
      ),
    );
    ok(await vault.runs.applySpace(runId: run, itemId: 'a', spaceId: 'arte'));
    ok(
      await vault.runs.completeReference(
        runId: run,
        itemId: 'a',
        extracted: const ExtractedMetadata(
          reference: ReferenceData(publisher: 'Planeta'),
        ),
      ),
    );
    await vault.runs.finishRun(run);
    return run;
  }

  Future<String> reviewRun(String itemId) async => ok(
    await vault.runs.startRun(
      itemId,
      model: 'gemini-3.8-flash',
      scope: AiRunScope.review,
    ),
  );

  Future<List<CorrectionSuggestion>> correctionsOf(String itemId) async => [
    ...ok(
      await vault.suggestions.suggestionsFor(itemId),
    ).whereType<CorrectionSuggestion>(),
  ];

  test('le da al revisor lo de la IA con las palabras del pedido, y lo que '
      'propone se puede aceptar tal cual', () async {
    await organizeA();
    final run = await reviewRun('a');
    reviewer.verdictFor = (index, thing) => switch (thing.subject) {
      CorrectionSubject.relation => ThingCorrection(
        index: index,
        reason: 'Lo discute.',
        value: 'contradice',
        note: 'Dicen lo contrario.',
      ),
      CorrectionSubject.property => ThingCorrection(
        index: index,
        reason: 'Es una novela.',
        value: 'Novela',
      ),
      CorrectionSubject.space => ThingCorrection(
        index: index,
        reason: 'Es literatura.',
        value: 'Literatura',
      ),
      CorrectionSubject.reference => ThingRemoval(
        index: index,
        reason: 'No dice la editorial.',
      ),
      _ => null,
    };

    final report = await step.review(
      ok(await vault.library.findById('a'))!,
      runId: run,
      model: 'gemini-3.8-flash',
    );

    expect(report, const AiStepReport(forReview: 4));
    final call = reviewer.calls.single;
    expect(call.title, 'Rayuela');
    expect(call.excerpt, 'Una novela larga.');
    final [relation, tag, space, reference] = call.things;
    expect(relation.name, 'vínculo con «Cortázar»');
    expect((relation.value, relation.note), ('relacionado', 'El autor.'));
    expect(relation.options, [
      'relacionado',
      'continua',
      'contradice',
      'cita',
      'resume',
    ]);
    expect(relation.context, 'Un escritor.');
    expect((tag.name, tag.value), ('etiqueta', 'Cuento'));
    expect(tag.options, containsAll(['Cuento', 'Novela']));
    expect((space.name, space.value), ('tema de la biblioteca', 'Arte'));
    expect(space.options, ['Arte', 'Literatura']);
    expect(
      (reference.name, reference.value),
      ('Editorial de la referencia', 'Planeta'),
    );

    final corrections = await correctionsOf('a');
    expect(corrections, hasLength(4));
    expect({for (final c in corrections) c.model}, {'gemini-3.8-flash'});
    expect({for (final c in corrections) c.aiRunId}, {run});
    expect(
      corrections
          .firstWhere((c) => c.subject == CorrectionSubject.relation)
          .label,
      'Cortázar',
    );
    for (final correction in corrections) {
      expect(
        await vault.suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
        reason: correction.subject.name,
      );
    }
    final link = await vault.db.select(vault.db.relations).getSingle();
    expect(
      (link.kind, link.note),
      (RelationKind.contradicts, 'Dicen lo contrario.'),
    );
    expect((await vault.reload('a')).spaceId, 'lit');
    expect((await ReferenceReader(vault.db).read('a')).publisher, isNull);
    expect(
      [for (final tag in (await vault.reload('a')).tags) tag.name],
      ['Novela'],
    );
  });

  test('no vuelve a proponer lo que está para decidir ni lo que la persona '
      'descartó, y deja afuera lo que hizo el revisor', () async {
    await organizeA();
    reviewer.verdictFor = (index, thing) =>
        thing.subject == CorrectionSubject.property
        ? ThingCorrection(index: index, reason: 'Novela.', value: 'Novela')
        : thing.subject == CorrectionSubject.reference
        ? ThingRemoval(index: index, reason: 'Sobra.')
        : null;
    final item = ok(await vault.library.findById('a'))!;
    await step.review(item, runId: await reviewRun('a'));
    expect(await correctionsOf('a'), hasLength(2));
    final tagFix = (await correctionsOf(
      'a',
    )).firstWhere((c) => c.subject == CorrectionSubject.property);
    await vault.suggestions.reject(tagFix.id);

    // Otra revisión: lo pendiente no se manda, y lo descartado no vuelve.
    reviewer.calls.clear();
    expect(
      await step.review(item, runId: await reviewRun('a')),
      AiStepReport.nothing,
    );
    expect([
      for (final thing in reviewer.calls.single.things) thing.subject,
    ], isNot(contains(CorrectionSubject.reference)));
    expect(
      (await correctionsOf(
        'a',
      )).where((c) => c.status == SuggestionStatus.pending),
      hasLength(1),
    );

    // Lo de Gemma no lo mira Gemma.
    reviewer.calls.clear();
    expect(
      await step.review(
        item,
        runId: await reviewRun('a'),
        exceptMadeBy: 'Gemma 4 E4B',
      ),
      AiStepReport.nothing,
    );
    expect(reviewer.calls, isEmpty);
  });

  test('de a tantas cosas por pedido como el modelo escribe', () async {
    final run = ok(await vault.runs.startRun('a', model: 'Gemma 4 E4B'));
    for (var i = 0; i < 6; i++) {
      ok(
        await vault.organize.assignProperty(
          itemId: 'a',
          definitionId: tema,
          value: 'Etiqueta $i',
          origin: ItemPropertyOrigin.ai,
          aiRunId: run,
        ),
      );
    }
    final item = ok(await vault.library.findById('a'))!;

    await step.review(item, runId: await reviewRun('a'));
    expect([for (final call in reviewer.calls) call.things.length], [4, 2]);

    reviewer.calls.clear();
    budget = const ModelTextBudget(partChars: 60000, maxDraftsPerCall: 8);
    await step.review(item, runId: await reviewRun('a'));
    expect([for (final call in reviewer.calls) call.things.length], [6]);
  });

  test(
    'la introducción de una nota mapa va con lo que reúne, y no se saca',
    () async {
      final historia = await AtlasTopics(vault.db).add('Historia antigua');
      final note = ok(
        await atlas.createMapNote(
          valueId: historia,
          title: 'Mapa de Historia antigua',
          blocks: const [
            ContentBlock.paragraph(text: 'Lo que dice la IA.'),
            ContentBlock.heading(text: 'Roma', level: 2),
            ContentBlock.bulletItem(text: '[[Las legiones]]'),
          ],
          model: 'gemma',
        ),
      )!;
      reviewer.verdictFor = (index, thing) => ThingCorrection(
        index: index,
        reason: 'Más clara.',
        value: 'Una introducción mejor.',
      );

      await step.review(
        ok(await vault.library.findById(note))!,
        runId: await reviewRun(note),
      );

      final thing = reviewer.calls.single.things.single;
      expect(thing.subject, CorrectionSubject.mapIntro);
      expect(thing.canRemove, isFalse);
      expect(thing.context, 'Roma, Las legiones');
      final correction = (await correctionsOf(note)).single;
      expect(
        await vault.suggestions.accept(correction.id),
        right<Failure, Unit>(unit),
      );
    },
  );

  test('sin nada de la IA, no le pide nada al revisor', () async {
    expect(
      await step.review(
        ok(await vault.library.findById('a'))!,
        runId: await reviewRun('a'),
      ),
      AiStepReport.nothing,
    );
    expect(reviewer.calls, isEmpty);
  });
}

T ok<T>(Either<Failure, T> result) =>
    result.getOrElse((failure) => fail('$failure'));
