import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/extracted_text_format.dart';

void main() {
  Source source(SourceKind kind, [String? file]) => Source(
    id: 's',
    kind: kind,
    capturedAt: DateTime(2026, 9, 30),
    originalFilePath: file,
  );

  group('extractedTextIsMarkdown (F22)', () {
    test('Markdown: notas, páginas web, y Word, EPUB y .md convertidos', () {
      expect(extractedTextIsMarkdown(source(SourceKind.manualNote)), isTrue);
      expect(extractedTextIsMarkdown(source(SourceKind.webPage)), isTrue);
      for (final file in ['a.docx', 'b.EPUB', 'c.md', 'd.markdown']) {
        expect(
          extractedTextIsMarkdown(source(SourceKind.document, 'x/$file')),
          isTrue,
          reason: file,
        );
      }
    });

    test('tal cual: transcripciones, fotos, PDF, .txt y publicaciones', () {
      for (final kind in [
        SourceKind.youtube,
        SourceKind.audio,
        SourceKind.video,
        SourceKind.image,
        SourceKind.socialPost,
      ]) {
        expect(extractedTextIsMarkdown(source(kind)), isFalse, reason: '$kind');
      }
      expect(
        extractedTextIsMarkdown(source(SourceKind.document, 'libro.pdf')),
        isFalse,
      );
      expect(
        extractedTextIsMarkdown(source(SourceKind.document, 'notas.txt')),
        isFalse,
      );
      expect(extractedTextIsMarkdown(source(SourceKind.document)), isFalse);
    });
  });

  group('isTranscriptSource', () {
    test('un TikTok o un reel lo es si se guardó su video; con solo su '
        'foto, no (F24)', () {
      expect(
        isTranscriptSource(source(SourceKind.socialPost, 'originales/a/r.mp4')),
        isTrue,
      );
      expect(
        isTranscriptSource(source(SourceKind.socialPost, 'originales/a/f.jpg')),
        isFalse,
      );
      expect(isTranscriptSource(source(SourceKind.socialPost)), isFalse);
    });

    test('además, solo YouTube, audio y video', () {
      expect(isTranscriptSource(source(SourceKind.youtube)), isTrue);
      expect(isTranscriptSource(source(SourceKind.audio)), isTrue);
      expect(isTranscriptSource(source(SourceKind.video)), isTrue);
      expect(isTranscriptSource(source(SourceKind.document)), isFalse);
      expect(isTranscriptSource(source(SourceKind.manualNote)), isFalse);
    });
  });
}
