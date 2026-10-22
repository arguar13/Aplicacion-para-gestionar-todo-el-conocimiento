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

  test('se estudia un documento y una página web (decisión E)', () {
    expect(studyRendition(item(SourceKind.document))?.id, 'rend-1');
    expect(studyRendition(item(SourceKind.webPage))?.id, 'rend-1');
  });

  test('un video, un audio o una nota, no', () {
    for (final kind in [
      SourceKind.youtube,
      SourceKind.audio,
      SourceKind.manualNote,
      SourceKind.socialPost,
    ]) {
      expect(studyRendition(item(kind)), isNull, reason: '$kind');
    }
  });

  test('sin texto, tampoco', () {
    expect(studyRendition(item(SourceKind.webPage, content: '  ')), isNull);
  });
}
