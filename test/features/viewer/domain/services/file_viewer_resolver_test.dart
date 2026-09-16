import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';
import 'package:sinapsis/features/viewer/domain/services/file_viewer_resolver.dart';

import '../../../../support/in_memory_file_store.dart';

void main() {
  late InMemoryFileStore files;
  late FileViewerResolver resolver;

  setUp(() {
    files = InMemoryFileStore();
    resolver = FileViewerResolver(files: files);
  });

  KnowledgeItem buildItem({
    required SourceKind kind,
    String? originalFilePath,
    List<Rendition> renditions = const [],
  }) {
    return KnowledgeItem(
      id: 'item-1',
      title: 'Un elemento',
      source: Source(
        id: 'source-1',
        kind: kind,
        capturedAt: DateTime(2026, 9, 14),
        originalFilePath: originalFilePath,
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 9, 14),
      updatedAt: DateTime(2026, 9, 14),
      renditions: renditions,
    );
  }

  test('sin ruta de archivo original, no hay nada que resolver', () async {
    final item = buildItem(kind: SourceKind.document);

    expect(await resolver.resolve(item), const NoResolvedViewer());
  });

  test('una imagen resuelve a su ruta absoluta', () async {
    final item = buildItem(
      kind: SourceKind.image,
      originalFilePath: 'originales/item-1/foto.jpg',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<ImageResolvedViewer>().having(
        (v) => v.path,
        'path',
        '/memoria/originales/item-1/foto.jpg',
      ),
    );
  });

  test('un audio resuelve a un reproductor sin video', () async {
    final item = buildItem(
      kind: SourceKind.audio,
      originalFilePath: 'originales/item-1/audio.mp3',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<MediaResolvedViewer>()
          .having((v) => v.isVideo, 'isVideo', isFalse)
          .having(
            (v) => v.path,
            'path',
            '/memoria/originales/item-1/audio.mp3',
          ),
    );
  });

  test('un video resuelve a un reproductor con video', () async {
    final item = buildItem(
      kind: SourceKind.video,
      originalFilePath: 'originales/item-1/video.mp4',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<MediaResolvedViewer>().having((v) => v.isVideo, 'isVideo', isTrue),
    );
  });

  test('una página archivada resuelve al HTML guardado', () async {
    final item = buildItem(
      kind: SourceKind.webPage,
      originalFilePath: 'originales/item-1/pagina.html',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<WebPageResolvedViewer>().having(
        (v) => v.path,
        'path',
        '/memoria/originales/item-1/pagina.html',
      ),
    );
  });

  test('un video de YouTube resuelve a un reproductor sin video', () async {
    final item = buildItem(
      kind: SourceKind.youtube,
      originalFilePath: 'originales/item-1/audio.m4a',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<MediaResolvedViewer>().having((v) => v.isVideo, 'isVideo', isFalse),
    );
  });

  test('una publicación social resuelve a un reproductor con video', () async {
    final item = buildItem(
      kind: SourceKind.socialPost,
      originalFilePath: 'originales/item-1/reel.mp4',
    );

    final resolved = await resolver.resolve(item);

    expect(
      resolved,
      isA<MediaResolvedViewer>().having((v) => v.isVideo, 'isVideo', isTrue),
    );
  });

  test('una nota manual nunca resuelve a un visor', () async {
    final item = buildItem(
      kind: SourceKind.manualNote,
      originalFilePath: 'originales/item-1/nota.txt',
    );

    expect(await resolver.resolve(item), const NoResolvedViewer());
  });

  group('documentos', () {
    test(
      'un PDF resuelve a su ruta absoluta sin tocar las renditions',
      () async {
        final path = await files.save(
          bytes: Uint8List.fromList('%PDF-1.7 contenido'.codeUnits),
          suggestedName: 'archivo.pdf',
          id: 'item-1',
        );
        final item = buildItem(
          kind: SourceKind.document,
          originalFilePath: path,
        );

        final resolved = await resolver.resolve(item);

        expect(
          resolved,
          isA<PdfResolvedViewer>().having(
            (v) => v.path,
            'path',
            '/memoria/$path',
          ),
        );
      },
    );

    test(
      'un DOCX con texto ya extraído resuelve al contenido, no al archivo',
      () async {
        final path = await files.save(
          bytes: Uint8List.fromList('contenido binario de un docx'.codeUnits),
          suggestedName: 'archivo.docx',
          id: 'item-1',
        );
        final item = buildItem(
          kind: SourceKind.document,
          originalFilePath: path,
          renditions: [
            Rendition.text(
              id: 'rend-1',
              itemId: 'item-1',
              kind: RenditionKind.markdown,
              content: 'El contenido ya extraído del documento.',
              isPrimary: true,
              createdAt: DateTime(2026),
            ),
          ],
        );

        final resolved = await resolver.resolve(item);

        expect(
          resolved,
          isA<TextResolvedViewer>().having(
            (v) => v.content,
            'content',
            'El contenido ya extraído del documento.',
          ),
        );
      },
    );

    test(
      'un documento sin ninguna forma de texto todavía no resuelve a nada',
      () async {
        final path = await files.save(
          bytes: Uint8List.fromList('contenido binario de un docx'.codeUnits),
          suggestedName: 'archivo.docx',
          id: 'item-1',
        );
        final item = buildItem(
          kind: SourceKind.document,
          originalFilePath: path,
        );

        expect(await resolver.resolve(item), const NoResolvedViewer());
      },
    );

    test('una rendition de texto secundaria (no primaria) no cuenta', () async {
      final path = await files.save(
        bytes: Uint8List.fromList('contenido binario de un docx'.codeUnits),
        suggestedName: 'archivo.docx',
        id: 'item-1',
      );
      final item = buildItem(
        kind: SourceKind.document,
        originalFilePath: path,
        renditions: [
          Rendition.text(
            id: 'rend-1',
            itemId: 'item-1',
            kind: RenditionKind.markdown,
            content: 'No es la primaria.',
            isPrimary: false,
            createdAt: DateTime(2026),
          ),
        ],
      );

      expect(await resolver.resolve(item), const NoResolvedViewer());
    });

    test('el archivo original ya no está: no rompe, no muestra nada', () async {
      final item = buildItem(
        kind: SourceKind.document,
        originalFilePath: 'originales/item-1/no-existe.pdf',
      );

      expect(await resolver.resolve(item), const NoResolvedViewer());
    });
  });
}
