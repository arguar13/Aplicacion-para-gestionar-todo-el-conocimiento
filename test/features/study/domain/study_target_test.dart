import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';

void main() {
  KnowledgeItem item(SourceKind kind, {String content = 'Un texto.'}) =>
      KnowledgeItem(
        id: 'item-1',
        title: 'Algo',
        source: Source(id: 'src-1', kind: kind, capturedAt: DateTime(2026)),
        processingState: ProcessingState.ready,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        renditions: [
          Rendition.text(
            id: 'rend-1',
            itemId: 'item-1',
            kind: RenditionKind.markdown,
            content: content,
            isPrimary: true,
            createdAt: DateTime(2026),
          ),
        ],
      );

  test('se estudia todo lo que trae un texto propio: un documento, una '
      'página, una publicación, una imagen, un audio, un video (F39)', () {
    for (final kind in [
      SourceKind.document,
      SourceKind.webPage,
      SourceKind.socialPost,
      SourceKind.image,
      SourceKind.audio,
      SourceKind.video,
      SourceKind.youtube,
    ]) {
      expect(studyRendition(item(kind))?.id, 'rend-1', reason: '$kind');
    }
  });

  test('una nota o una referencia, no', () {
    for (final kind in [SourceKind.manualNote, SourceKind.reference]) {
      expect(studyRendition(item(kind)), isNull, reason: '$kind');
    }
  });

  test('sin texto, tampoco', () {
    expect(studyRendition(item(SourceKind.webPage, content: '  ')), isNull);
  });
}
