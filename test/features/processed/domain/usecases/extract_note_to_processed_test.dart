import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/extract_note_target.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/usecases/extract_note_to_processed.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';

import '../../../../support/library_harness.dart';

const _content = 'La primera idea. La segunda idea es larga. La tercera.';

/// «Extraer como nota» desde cualquier pantalla (F41, decisión J), sin
/// pantalla: adónde va según qué es el elemento, que nunca tría la fuente, y
/// que su deshacer saca solo esa nota. Contra la base real del arnés.
void main() {
  late LibraryHarness harness;
  final now = DateTime(2026, 10, 27, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> save(String id, SourceKind kind) => harness.container
      .read(libraryRepositoryProvider)
      .save(
        KnowledgeItem(
          id: id,
          title: 'Elemento $id',
          source: Source(id: 's-$id', kind: kind, capturedAt: now),
          processingState: ProcessingState.ready,
          createdAt: now,
          updatedAt: now,
          renditions: [
            Rendition.text(
              id: 'rend-$id',
              itemId: id,
              kind: RenditionKind.plainText,
              content: _content,
              isPrimary: true,
              createdAt: now,
            ),
          ],
        ),
      );

  ExtractNoteToProcessed extract() =>
      harness.container.read(extractNoteToProcessedProvider);

  Future<ExtractNoteOutcome> note(String id, int start, int end) async =>
      (await extract()(
        itemId: id,
        renditionId: 'rend-$id',
        start: start,
        end: end,
        excerpt: _content.substring(start, end),
      )).getRight().toNullable()!;

  Future<List<String>> notes() async => [
    for (final part
        in await (harness.database.select(harness.database.processedParts)
              ..where((p) => p.section.equalsValue(ProcessedSection.notes))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get())
      part.content,
  ];

  Future<int> documents() async =>
      (await harness.database.select(harness.database.processedDocuments).get())
          .length;

  Future<ItemState> stateOf(String id) async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle()).state;

  group('adónde va', () {
    test('de una fuente viva, a su documento procesado', () async {
      await save('fuente', SourceKind.document);

      expect(
        (await harness.container
                .read(processedRepositoryProvider)
                .extractTargetOf('fuente'))
            .getRight()
            .toNullable(),
        const ExtractToSource('fuente'),
      );
    });

    test('de una fuente en la papelera, a ningún lado', () async {
      await save('fuente', SourceKind.document);
      await harness.container.read(libraryRepositoryProvider).delete('fuente');

      final outcome = await note('fuente', 0, 16);

      expect(outcome, isA<ExtractRefusedInTrash>());
      expect(await documents(), 0);
    });

    test('de una nota propia, a una nota suelta', () async {
      await save('mia', SourceKind.manualNote);

      expect(await note('mia', 0, 16), isA<ExtractLooseNote>());
      expect(await documents(), 0);
    });

    test('de algo que no existe, un fallo', () async {
      final outcome = await extract()(
        itemId: 'no-existe',
        renditionId: 'r',
        start: 0,
        end: 1,
        excerpt: 'x',
      );

      expect(outcome.isLeft(), isTrue);
    });
  });

  group('de una fuente', () {
    test('el documento nace con esa sola nota, tal cual y con su ancla, y la '
        'fuente sigue en la Bandeja', () async {
      await save('fuente', SourceKind.document);
      final before = await stateOf('fuente');

      final outcome = await note('fuente', 17, 42) as ExtractedToProcessed;

      expect(outcome.created, isTrue);
      expect(outcome.documentId, processedDocumentIdFor('fuente'));
      expect(await notes(), ['La segunda idea es larga.']);
      final part = await harness.database
          .select(harness.database.processedParts)
          .getSingle();
      expect((part.sourceStart, part.sourceEnd), (17, 42));
      expect(part.sourceRenditionId, 'rend-fuente');
      // Literal, de la fuente: «Actualizar» sabe que es copiado.
      expect(part.origin, ProcessedPartOrigin.copied);
      expect(await stateOf('fuente'), before);
    });

    test(
      'con el documento ya armado, se suma al final sin tocar lo demás',
      () async {
        await save('fuente', SourceKind.document);
        await harness.container.read(processSourceUseCaseProvider)('fuente', {
          ProcessedSection.text: SectionEdit.add(
            const SectionInput.fromSource(),
          ),
        });

        final outcome = await note('fuente', 0, 16) as ExtractedToProcessed;

        expect(outcome.created, isFalse);
        expect(await notes(), ['La primera idea.']);
        final text = await (harness.database.select(
          harness.database.processedParts,
        )..where((p) => p.section.equalsValue(ProcessedSection.text))).get();
        expect(text.single.content, _content);
      },
    );

    test('el mismo pasaje no entra dos veces', () async {
      await save('fuente', SourceKind.document);
      await note('fuente', 0, 16);

      final again = await note('fuente', 0, 16) as ExtractedToProcessed;

      expect(again.unchanged, isTrue);
      expect(await notes(), ['La primera idea.']);
    });

    test('deshacer la primera saca la nota y el documento que nació para '
        'ella', () async {
      await save('fuente', SourceKind.document);
      final first = await note('fuente', 0, 16) as ExtractedToProcessed;

      expect((await extract().undo(first.undo)).isRight(), isTrue);

      expect(await documents(), 0);
    });

    test('deshacer la segunda saca solo esa: la otra y el documento '
        'quedan', () async {
      await save('fuente', SourceKind.document);
      await note('fuente', 0, 16);
      final second = await note('fuente', 17, 42) as ExtractedToProcessed;

      await extract().undo(second.undo);

      expect(await documents(), 1);
      expect(await notes(), ['La primera idea.']);
    });
  });

  test('de un documento procesado, a sus propias notas, como algo suyo '
      '(decisión I)', () async {
    await save('fuente', SourceKind.document);
    await note('fuente', 0, 16);
    final documentId = processedDocumentIdFor('fuente');

    final outcome = await extract()(
      itemId: documentId,
      renditionId: 'lo-que-se-ve',
      start: 0,
      end: 9,
      excerpt: 'Mi pasaje',
    );

    expect(outcome.getRight().toNullable(), isA<ExtractedToProcessed>());
    final parts = await (harness.database.select(
      harness.database.processedParts,
    )..orderBy([(p) => OrderingTerm.asc(p.position)])).get();
    expect(
      [for (final p in parts) p.content],
      ['La primera idea.', 'Mi pasaje'],
    );
    // Lo suyo no lleva ancla en la fuente: el texto que se ve ahí es del
    // documento.
    expect(parts.last.sourceRenditionId, isNull);
    expect(parts.last.origin, ProcessedPartOrigin.user);
  });
}
