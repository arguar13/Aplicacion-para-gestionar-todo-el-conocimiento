import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/ai_organize/data/services/vocabulary_candidates.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_properties_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/vocabulary_budget.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

import '../../../../support/ai_organize_harness.dart';
import '../../../../support/fake_embedding_service.dart';

/// Un modelo de propiedades de mentira que además guarda el texto y el
/// vocabulario que vio.
class _RecordingPropertyModel implements PropertySuggestionService {
  List<PropertyDraft> drafts = const [];
  final contents = <String>[];
  final vocabularies = <List<PropertyVocabularyCategory>>[];

  @override
  Future<List<PropertyDraft>> suggestProperties({
    required String itemTitle,
    required String itemContent,
    required List<PropertyVocabularyCategory> categories,
  }) async {
    contents.add(itemContent);
    vocabularies.add(categories);
    return drafts;
  }
}

/// Los vectores de mentira: lo que habla del Senado apunta para un lado, el
/// resto para el otro.
List<double> _vectorFor(String text) =>
    text.contains('Senado') || text.contains('senatorial') ? [1, 0] : [0, 1];

void main() {
  late AiOrganizeHarness vault;
  late _RecordingPropertyModel model;
  late AutoPropertiesStep step;
  late String epoca;

  setUp(() async {
    vault = AiOrganizeHarness();
    model = _RecordingPropertyModel();
    step = AutoPropertiesStep(
      vocabulary: VocabularyCandidatesReader(
        database: vault.db,
        embeddings: FakeEmbeddingService(vectorFor: _vectorFor),
        clock: vault.clock,
      ),
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

  group('un vocabulario de miles de valores', () {
    /// Tres mil valores de Época que no tienen nada que ver, de una vez.
    Future<void> thousands() => vault.db.batch((b) {
      b.insertAll(vault.db.propertyValues, [
        for (var i = 0; i < 3000; i++)
          PropertyValuesCompanion.insert(
            id: 'v$i',
            definitionId: epoca,
            value: 'Valor ${'$i'.padLeft(4, '0')}',
            createdAt: vault.now,
          ),
      ]);
    });

    List<String> epochsIn(List<PropertyVocabularyCategory> categories) =>
        categories.singleWhere((c) => c.name == 'Época').values;

    String described(List<PropertyVocabularyCategory> categories) =>
        categories.map(describeVocabularyCategory).join('\n');

    test('el modelo ve lo pertinente, dentro del tope', () async {
      await thousands();
      await vault.organize.assignProperty(
        itemId: 'otro',
        definitionId: epoca,
        value: 'Roma',
      );
      final item = await vault.source(
        'a',
        title: 'El Senado',
        content: 'El Senado de Roma y sus leyes.',
      );

      await step.organize(item, runId: await vault.startRun('a'));

      final seen = model.vocabularies.single;
      expect(
        described(seen).length,
        lessThanOrEqualTo(kPropertyVocabularyBudgetChars),
      );
      final values = epochsIn(seen);
      // Lo que el texto nombra va primero; después, lo más usado.
      expect(values.first, 'Roma');
      expect(values, contains('Antigua'));
      expect(values.length, lessThan(3002));
    });

    test('los vectores del vocabulario se calculan de a partes, y lo cercano '
        'entra cuando lo tiene', () async {
      await thousands();
      // Cerca del Senado por sus vectores, sin que el texto lo nombre, sin
      // usar y último en el orden: es lo último que se describe.
      await vault.db
          .into(vault.db.propertyValues)
          .insert(
            PropertyValuesCompanion.insert(
              id: 'zona',
              definitionId: epoca,
              value: 'Zona senatorial',
              createdAt: vault.now,
            ),
          );
      final item = await vault.source(
        'a',
        title: 'El Senado',
        content: 'Las leyes del Senado.',
      );

      await step.organize(item, runId: await vault.startRun('a'));
      expect(
        await vault.db.select(vault.db.propertyValueEmbeddings).get(),
        hasLength(kMaxNewValueVectorsPerItem),
      );

      var passes = 1;
      while ((await vault.db.select(vault.db.propertyValueEmbeddings).get())
              .length <
          3002) {
        await step.organize(item, runId: await vault.startRun('a'));
        passes++;
      }
      expect(passes, (3002 / kMaxNewValueVectorsPerItem).ceil());
      await step.organize(item, runId: await vault.startRun('a'));

      expect(
        epochsIn(model.vocabularies.first),
        isNot(contains('Zona senatorial')),
      );
      expect(epochsIn(model.vocabularies.last), contains('Zona senatorial'));
    });

    test('un valor renombrado se describe de nuevo', () async {
      final item = await vault.source(
        'a',
        title: 'El Senado',
        content: 'Las leyes del Senado.',
      );
      await step.organize(item, runId: await vault.startRun('a'));
      final antigua = await vault.db
          .select(vault.db.propertyValueEmbeddings)
          .getSingle();
      expect(antigua.label, 'Antigua');

      await (vault.db.update(vault.db.propertyValues)
            ..where((v) => v.id.equals(antigua.valueId)))
          .write(const PropertyValuesCompanion(value: Value('Edad antigua')));
      await step.organize(item, runId: await vault.startRun('a'));

      final renamed = await vault.db
          .select(vault.db.propertyValueEmbeddings)
          .getSingle();
      expect(renamed.label, 'Edad antigua');
    });
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
