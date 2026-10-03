import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_properties_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

import '../../../../support/ai_organize_harness.dart';

/// Un modelo de propiedades de mentira que además guarda el texto que vio.
class _RecordingPropertyModel implements PropertySuggestionService {
  List<PropertyDraft> drafts = const [];
  final contents = <String>[];

  @override
  Future<List<PropertyDraft>> suggestProperties({
    required String itemTitle,
    required String itemContent,
    required List<PropertyVocabularyCategory> categories,
  }) async {
    contents.add(itemContent);
    return drafts;
  }
}

void main() {
  late AiOrganizeHarness vault;
  late _RecordingPropertyModel model;
  late AutoPropertiesStep step;
  late String epoca;

  setUp(() async {
    vault = AiOrganizeHarness();
    model = _RecordingPropertyModel();
    step = AutoPropertiesStep(
      database: vault.db,
      service: model,
      organize: vault.organize,
      suggestions: vault.suggestions,
      runs: vault.runs,
    );
    epoca = (await vault.organize.getOrCreatePropertyDefinition(
      'Época',
    )).getOrElse((f) => fail('$f')).id;
    // El vocabulario de la persona: «Antigua» ya existe, con un alias.
    await vault.source('otro', title: 'Otro', content: 'x');
    await vault.organize.assignProperty(
      itemId: 'otro',
      definitionId: epoca,
      value: 'Antigua',
    );
  });

  tearDown(() => vault.close());

  PropertyDraft draft(String value) =>
      PropertyDraft(definitionId: epoca, definitionName: 'Época', value: value);

  test('un valor del vocabulario se asigna solo; uno nuevo queda para '
      'revisar', () async {
    final item = await vault.source('a', title: 'Roma', content: 'Roma.');
    model.drafts = [draft('antigua'), draft('Clásica')];
    final run = await vault.startRun('a');

    final report = await step.organize(item, runId: run);

    expect(report, const AiStepReport(applied: 1, forReview: 1));
    final assigned = (await vault.reload('a')).properties.single;
    expect(assigned.value, 'Antigua');
    expect(assigned.origin, ItemPropertyOrigin.ai);
    expect(assigned.aiRunId, run);
    final review =
        (await vault.suggestions.watchPendingSuggestions('a').first).single
            as PropertySuggestion;
    expect((review.value, review.isNewValue), ('Clásica', true));
  });

  test('no repite lo que ya tiene, lo propuesto ni lo que «no era»', () async {
    await vault.source('a', title: 'Roma', content: 'Roma.');
    // Lo propuesto antes, y descartado en «Para revisar».
    final proposal = (await vault.suggestions.createPropertySuggestion(
      targetItemId: 'a',
      definitionId: epoca,
      definitionName: 'Época',
      value: 'Clásica',
      isNewValue: true,
    )).getOrElse((f) => fail('$f'));
    await vault.suggestions.reject(proposal.id);
    // Lo que la IA puso antes y la persona dijo que «no era».
    await vault.organize.assignProperty(
      itemId: 'a',
      definitionId: epoca,
      value: 'Antigua',
      origin: ItemPropertyOrigin.ai,
      aiRunId: await vault.startRun('a'),
    );
    final wrong = (await vault.reload('a')).properties.single;
    await vault.organize.rejectAiProperty(
      itemId: 'a',
      propertyValueId: wrong.valueId,
    );
    model.drafts = [draft('Antigua'), draft('clásica')];

    final report = await step.organize(
      await vault.reload('a'),
      runId: await vault.startRun('a'),
    );

    expect(report, AiStepReport.nothing);
    expect((await vault.reload('a')).properties, isEmpty);
  });

  test('no le pisa a la persona lo que ya puso', () async {
    await vault.source('a', title: 'Roma', content: 'Roma.');
    await vault.organize.assignProperty(
      itemId: 'a',
      definitionId: epoca,
      value: 'Antigua',
    );
    model.drafts = [draft('Antigua')];

    final report = await step.organize(
      await vault.reload('a'),
      runId: await vault.startRun('a'),
    );

    expect(report, AiStepReport.nothing);
    final kept = (await vault.reload('a')).properties.single;
    expect(kept.origin, ItemPropertyOrigin.manual);
  });

  test('de un texto largo, el modelo ve solo el comienzo', () async {
    final item = await vault.source(
      'libro',
      title: 'Libro',
      content: 'palabra ' * 5000,
    );

    await step.organize(item, runId: await vault.startRun('libro'));

    expect(
      model.contents.single.length,
      lessThanOrEqualTo(kPropertyExcerptChars + 1),
    );
  });
}
