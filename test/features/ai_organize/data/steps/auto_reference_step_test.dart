import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
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
      runs: vault.runs,
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

    final report = await step.organize(item, runId: await vault.startRun('a'));

    // La autora y el año: dos datos.
    expect(report.applied, 2);
    expect((await vault.reload('a')).source.publishedAt?.year, 2015);
    final authors = (await ReferenceReader(vault.db).read('a')).contributors;
    expect(authors.single.name.label, 'Beard, Mary');
  });

  test('la pendiente que dejó el procesamiento queda aceptada', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );
    await vault.suggestions.createMetadataSuggestion(
      targetItemId: 'a',
      extracted: const ExtractedMetadata(title: 'El Senado romano'),
    );

    await step.organize(item, runId: await vault.startRun('a'));

    final suggestion = (await metadataOf('a')).single;
    expect(suggestion.status, SuggestionStatus.accepted);
  });

  test('nunca pisa lo que escribió la persona', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );
    await KnowledgeEntryWriter(vault.db).setReference(
      'a',
      const ReferenceData(
        contributors: [Contributor(name: PersonName(family: 'Gibbon'))],
      ),
    );

    final report = await step.organize(item, runId: await vault.startRun('a'));

    // Solo el año: la autora ya estaba.
    expect(report.applied, 1);
    final reference = await ReferenceReader(vault.db).read('a');
    expect(reference.contributors.single.name.label, 'Gibbon');
  });

  test(
    'si la persona dijo que la obra no tiene fecha, no le pone una',
    () async {
      final item = await vault.source(
        'a',
        title: 'Página',
        content: 'Texto.',
        originalFilePath: await archivedPage(),
      );
      await KnowledgeEntryWriter(vault.db).setReference(
        'a',
        const ReferenceData(publicationPrecision: PublicationPrecision.undated),
      );

      final report = await step.organize(
        item,
        runId: await vault.startRun('a'),
      );

      // Solo la autora.
      expect(report.applied, 1);
      expect((await vault.reload('a')).source.publishedAt, isNull);
      expect(
        (await ReferenceReader(vault.db).read('a')).publicationPrecision,
        PublicationPrecision.undated,
      );
    },
  );

  group('deshacer la pasada (v35)', () {
    test('vacía lo que completó y deja la fecha como estaba', () async {
      final item = await vault.source(
        'a',
        title: 'Página',
        content: 'Texto.',
        originalFilePath: await archivedPage(),
      );
      final run = await vault.startRun('a');
      await step.organize(item, runId: run);
      final finished = (await vault.runs.finishRun(
        run,
      )).getOrElse((f) => fail('$f'));
      expect(finished.referenceFields, 2);

      final undone = (await vault.runs.undoRun(
        run,
      )).getOrElse((f) => fail('$f'));

      expect(undone.referenceFields, 2);
      expect((await vault.reload('a')).source.publishedAt, isNull);
      final reference = await ReferenceReader(vault.db).read('a');
      expect(reference.contributors, isEmpty);
      expect(reference.publicationPrecision, isNull);
    });

    test('lo que la persona cambió después queda como lo dejó', () async {
      final item = await vault.source(
        'a',
        title: 'Página',
        content: 'Texto.',
        originalFilePath: await archivedPage(),
      );
      final run = await vault.startRun('a');
      await step.organize(item, runId: run);
      await vault.runs.finishRun(run);
      // La persona suma un autor; el año lo deja.
      final current = await ReferenceReader(vault.db).read('a');
      await KnowledgeEntryWriter(vault.db).setReference(
        'a',
        current.copyWith(
          contributors: [
            ...current.contributors,
            const Contributor(name: PersonName(family: 'Gibbon')),
          ],
        ),
      );
      final listed = (await vault.runs.listRuns(
        itemId: 'a',
      )).getOrElse((f) => fail('$f')).single;
      expect(listed.created.referenceFields, 2);
      expect(listed.remaining.referenceFields, 1);

      final undone = (await vault.runs.undoItem(
        'a',
      )).getOrElse((f) => fail('$f'));

      expect(undone.referenceFields, 1);
      expect((await vault.reload('a')).source.publishedAt, isNull);
      final reference = await ReferenceReader(vault.db).read('a');
      expect(reference.contributors, hasLength(2));
    });
  });

  test('lo ya aplicado no se repite', () async {
    final item = await vault.source(
      'a',
      title: 'Página',
      content: 'Texto.',
      originalFilePath: await archivedPage(),
    );
    await step.organize(item, runId: await vault.startRun('a'));
    // La persona borra la autora: fue a propósito.
    final reference = await ReferenceReader(vault.db).read('a');
    await KnowledgeEntryWriter(vault.db).setReference(
      'a',
      ReferenceData(
        type: reference.type,
        publicationPrecision: reference.publicationPrecision,
      ),
    );

    expect(
      await step.organize(item, runId: await vault.startRun('a')),
      AiStepReport.nothing,
    );
    expect((await ReferenceReader(vault.db).read('a')).contributors, isEmpty);
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

    expect(
      await step.organize(item, runId: await vault.startRun('a')),
      AiStepReport.nothing,
    );
    expect((await vault.reload('a')).source.publishedAt, isNull);
  });

  test('una nota no tiene referencia', () async {
    final note = await vault.note('n', title: 'Nota', content: 'Texto.');

    expect(
      await step.organize(note, runId: await vault.startRun('n')),
      AiStepReport.nothing,
    );
  });
}
