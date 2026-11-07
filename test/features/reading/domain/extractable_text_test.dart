import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';

/// Qué abre el lector de un elemento: el texto de una fuente o, desde F46
/// (paso 5j, decisión 2a), una nota de bloques con algo escrito.
void main() {
  final now = DateTime(2026, 11, 6);

  KnowledgeItem item(List<(RenditionKind, String)> texts) => KnowledgeItem(
    id: 'i',
    title: 'Algo',
    source: Source(id: 's', kind: SourceKind.manualNote, capturedAt: now),
    processingState: ProcessingState.ready,
    createdAt: now,
    updatedAt: now,
    renditions: [
      for (final (index, (kind, content)) in texts.indexed)
        Rendition.text(
          id: 'r$index',
          itemId: 'i',
          kind: kind,
          content: content,
          isPrimary: index == 0,
          createdAt: now,
        ),
    ],
  );

  String blocks(List<ContentBlock> blocks) => encodeContentBlocks(blocks);

  group('readableBlocksOf', () {
    test('una nota de bloques con algo escrito: su forma y sus bloques, '
        'también los vacíos —el lector los cuenta por su lugar—', () {
      const content = [
        ContentBlock.paragraph(text: ''),
        ContentBlock.paragraph(text: 'Algo.'),
      ];
      final note = readableBlocksOf(
        item([(RenditionKind.blocks, blocks(content))]),
      );

      expect(note?.rendition.id, 'r0');
      expect(note?.blocks, content);
    });

    test('vacía, o con solo espacios, no tiene nada que leer', () {
      for (final content in [
        const <ContentBlock>[],
        const [ContentBlock.paragraph(text: '')],
        const [ContentBlock.heading(text: '  \n ')],
      ]) {
        expect(
          readableBlocksOf(item([(RenditionKind.blocks, blocks(content))])),
          isNull,
          reason: '$content',
        );
      }
    });

    test('un JSON que no se puede leer no rompe nada: no se ofrece', () {
      expect(readableBlocksOf(item([(RenditionKind.blocks, '{roto')])), isNull);
    });

    test('el texto de una fuente no es una nota de bloques', () {
      expect(
        readableBlocksOf(item([(RenditionKind.plainText, 'Un texto.')])),
        isNull,
      );
    });

    test('entre varias formas, la de bloques', () {
      final note = readableBlocksOf(
        item([
          (RenditionKind.plainText, 'Otro texto.'),
          (
            RenditionKind.blocks,
            blocks(const [ContentBlock.paragraph(text: 'La nota.')]),
          ),
        ]),
      );
      expect(note?.rendition.id, 'r1');
    });
  });

  group('hasReadingText', () {
    test('el texto de una fuente, sí', () {
      expect(
        hasReadingText(item([(RenditionKind.plainText, 'Algo.')])),
        isTrue,
      );
    });

    test('una nota de bloques escrita, sí; vacía, no', () {
      expect(
        hasReadingText(
          item([
            (
              RenditionKind.blocks,
              blocks(const [ContentBlock.paragraph(text: 'Algo.')]),
            ),
          ]),
        ),
        isTrue,
      );
      expect(
        hasReadingText(
          item([
            (
              RenditionKind.blocks,
              blocks(const [ContentBlock.paragraph(text: '')]),
            ),
          ]),
        ),
        isFalse,
      );
    });

    test('sin ninguna forma de texto, no', () {
      expect(hasReadingText(item(const [])), isFalse);
    });
  });
}
