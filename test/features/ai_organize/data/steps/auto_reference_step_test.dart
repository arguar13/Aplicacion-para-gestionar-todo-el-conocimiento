import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/features/ai_organize/data/steps/auto_reference_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';

import '../../../../support/ai_organize_harness.dart';

const _page = '''
<html><head>
<meta name="citation_title" content="El Senado romano">
<meta name="citation_author" content="Mary Beard">
<meta name="citation_publication_date" content="2015">
</head><body>Texto.</body></html>''';

void main() {
  late AiOrganizeHarness vault;
  late AutoReferenceStep step;

  setUp(() {
    vault = AiOrganizeHarness();
    step = AutoReferenceStep(
      files: vault.files,
      suggestions: vault.suggestions,
    );
  });

  tearDown(() => vault.close());

  Future<String> archivedPage() => vault.files.save(
    bytes: Uint8List.fromList(utf8.encode(_page)),
    suggestedName: 'pagina.html',
    id: 'a',
  );

  Future<List<MetadataSuggestion>> metadataOf(String itemId) async =>
      (await vault.suggestions.suggestionsFor(
        itemId,
      )).getOrElse((f) => fail('$f')).whereType<MetadataSuggestion>().toList();

  test('completa sola la referencia con lo que lee de la página', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );

    final report = await step.organize(item, runId: 'run');

    expect(report.applied, 1);
    final suggestion = (await metadataOf('a')).single;
    expect(suggestion.status, SuggestionStatus.accepted);
    expect((await vault.reload('a')).source.publishedAt?.year, 2015);
  });

  test('lo ya aplicado no se repite', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );
    await step.organize(item, runId: 'run');

    expect(await step.organize(item, runId: 'run'), AiStepReport.nothing);
    expect(await metadataOf('a'), hasLength(1));
  });

  test('si la persona la descartó, no la aplica', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );
    // La que dejó el procesamiento, descartada en «Para revisar».
    final pending = (await vault.suggestions.createMetadataSuggestion(
      targetItemId: 'a',
      extracted: const ExtractedMetadata(title: 'El Senado romano'),
    )).getOrElse((f) => fail('$f'));
    await vault.suggestions.reject(pending.id);

    expect(await step.organize(item, runId: 'run'), AiStepReport.nothing);
    expect((await vault.reload('a')).source.publishedAt, isNull);
  });

  test('una nota no tiene referencia', () async {
    final note = await vault.note('n', title: 'Nota', content: 'Texto.');

    expect(await step.organize(note, runId: 'run'), AiStepReport.nothing);
  });
}
