import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';

void main() {
  group('mediaKindOf', () {
    test('manda el tipo del servidor', () {
      expect(
        mediaKindOf(contentType: 'application/pdf', fileName: 'x'),
        RenditionKind.pdf,
      );
      expect(
        mediaKindOf(contentType: 'audio/mpeg; x=1', fileName: 'x.jpg'),
        RenditionKind.audio,
      );
      expect(
        mediaKindOf(contentType: 'application/epub+zip', fileName: 'x'),
        RenditionKind.document,
      );
      expect(
        mediaKindOf(contentType: 'image/svg+xml', fileName: 'x'),
        RenditionKind.image,
      );
      expect(
        mediaKindOf(contentType: 'application/zip', fileName: 'x'),
        RenditionKind.file,
      );
    });

    test('una página es null', () {
      expect(mediaKindOf(contentType: 'text/html', fileName: 'a.pdf'), isNull);
      expect(mediaKindOf(fileName: 'index.html'), isNull);
    });

    test('sin tipo útil, decide la extensión', () {
      expect(
        mediaKindOf(contentType: 'application/octet-stream', fileName: 'a.mp3'),
        RenditionKind.audio,
      );
      expect(mediaKindOf(fileName: 'libro.epub'), RenditionKind.document);
      expect(mediaKindOf(fileName: 'raro.xyz'), RenditionKind.file);
    });
  });

  group('isFileResponse', () {
    test('lo que es un archivo', () {
      expect(
        isFileResponse(contentType: 'application/pdf', fileName: 'articulo'),
        isTrue,
      );
      expect(
        isFileResponse(
          contentType: 'application/octet-stream',
          fileName: 'a.zip',
        ),
        isTrue,
      );
      expect(isFileResponse(fileName: 'charla.mp3'), isTrue);
    });

    test('lo que es una página, o no se sabe', () {
      expect(
        isFileResponse(contentType: 'text/html', fileName: 'a.pdf'),
        isFalse,
      );
      expect(isFileResponse(fileName: 'articulo'), isFalse);
      expect(isFileResponse(fileName: 'raro.xyz'), isFalse);
      expect(
        isFileResponse(contentType: 'text/css', fileName: 'estilos'),
        isFalse,
      );
    });
  });

  test('isZipArchive e isReadableDocument', () {
    expect(isZipArchive(contentType: 'application/zip', fileName: 'x'), isTrue);
    expect(isZipArchive(fileName: 'datos.zip'), isTrue);
    expect(
      isZipArchive(contentType: 'application/epub+zip', fileName: 'a.epub'),
      isFalse,
    );
    expect(isReadableDocument(fileName: 'a.docx'), isTrue);
    expect(
      isReadableDocument(contentType: 'application/msword', fileName: 'a.doc'),
      isFalse,
    );
  });

  test('mediaKindOfUrl', () {
    expect(
      mediaKindOfUrl(Uri.parse('https://x.org/a/informe.PDF?v=2')),
      RenditionKind.pdf,
    );
    expect(mediaKindOfUrl(Uri.parse('https://x.org/wiki/Roma')), isNull);
    expect(mediaKindOfUrl(Uri.parse('https://x.org/')), isNull);
  });
}
