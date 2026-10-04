import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/item_thumbnail.dart';

import '../../../support/in_memory_file_store.dart';

void main() {
  late InMemoryFileStore files;
  Uint8List? renderedPage;
  var renderCalls = 0;

  late ItemThumbnailResolver resolver;

  setUp(() {
    files = InMemoryFileStore();
    renderedPage = Uint8List.fromList([1, 2, 3]);
    renderCalls = 0;
    resolver = ItemThumbnailResolver(
      files: files,
      renderPdfFirstPage: ({localPath, bytes}) async {
        renderCalls++;
        return renderedPage;
      },
    );
  });

  KnowledgeItem itemWith({
    required SourceKind kind,
    String? originalFilePath,
    String? url,
  }) {
    return KnowledgeItem(
      id: 'item-1',
      title: 'Un elemento',
      source: Source(
        id: 'src-1',
        kind: kind,
        capturedAt: DateTime(2026, 9, 11),
        url: url,
        originalFilePath: originalFilePath,
      ),
      processingState: ProcessingState.ready,
      createdAt: DateTime(2026, 9, 11),
      updatedAt: DateTime(2026, 9, 11),
    );
  }

  test('una imagen guardada en el disco se muestra desde el disco, sin traer '
      'sus bytes a memoria', () async {
    final onDisk = _DiskFileStore();
    final path = await onDisk.save(
      bytes: Uint8List.fromList([9, 9, 9]),
      suggestedName: 'foto.jpg',
      id: 'img-1',
    );
    final item = itemWith(kind: SourceKind.image, originalFilePath: path);

    final thumbnail = await ItemThumbnailResolver(
      files: onDisk,
      renderPdfFirstPage: ({localPath, bytes}) async => null,
    ).resolve(item);

    expect(thumbnail, isA<ItemThumbnailFile>());
    expect((thumbnail as ItemThumbnailFile).path, '/disco/$path');
    expect(onDisk.reads, 0);
  });

  test(
    'donde no hay disco (la web), una imagen trae sus propios bytes',
    () async {
      final path = await files.save(
        bytes: Uint8List.fromList([9, 9, 9]),
        suggestedName: 'foto.jpg',
        id: 'img-1',
      );
      final item = itemWith(kind: SourceKind.image, originalFilePath: path);

      final thumbnail = await resolver.resolve(item);

      expect(thumbnail, isA<ItemThumbnailBytes>());
      expect(
        (thumbnail as ItemThumbnailBytes).bytes,
        Uint8List.fromList([9, 9, 9]),
      );
    },
  );

  test('una imagen sin archivo original no tiene miniatura', () async {
    final item = itemWith(kind: SourceKind.image);

    final thumbnail = await resolver.resolve(item);

    expect(thumbnail, isA<ItemThumbnailNone>());
  });

  test('un PDF renderiza su primera página', () async {
    final path = await files.save(
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.4 contenido')),
      suggestedName: 'libro.pdf',
      id: 'doc-1',
    );
    final item = itemWith(kind: SourceKind.document, originalFilePath: path);

    final thumbnail = await resolver.resolve(item);

    expect(thumbnail, isA<ItemThumbnailBytes>());
    expect((thumbnail as ItemThumbnailBytes).bytes, renderedPage);
    expect(renderCalls, 1);
  });

  test('un documento que no es PDF no se renderiza', () async {
    final path = await files.save(
      bytes: Uint8List.fromList(utf8.encode('contenido de texto plano')),
      suggestedName: 'notas.txt',
      id: 'doc-2',
    );
    final item = itemWith(kind: SourceKind.document, originalFilePath: path);

    final thumbnail = await resolver.resolve(item);

    expect(thumbnail, isA<ItemThumbnailNone>());
    expect(renderCalls, 0);
  });

  test('un video de YouTube usa la miniatura pública del video', () async {
    final item = itemWith(
      kind: SourceKind.youtube,
      url: 'https://www.youtube.com/watch?v=abc123XYZ',
    );

    final thumbnail = await resolver.resolve(item);

    expect(thumbnail, isA<ItemThumbnailUrl>());
    expect(
      (thumbnail as ItemThumbnailUrl).url,
      'https://i.ytimg.com/vi/abc123XYZ/mqdefault.jpg',
    );
  });

  test('un enlace que no es de YouTube no tiene miniatura', () async {
    final item = itemWith(
      kind: SourceKind.youtube,
      url: 'https://ejemplo.org/no-es-youtube',
    );

    final thumbnail = await resolver.resolve(item);

    expect(thumbnail, isA<ItemThumbnailNone>());
  });

  test('una página web, un audio o una nota no tienen miniatura', () async {
    for (final kind in [
      SourceKind.webPage,
      SourceKind.socialPost,
      SourceKind.audio,
      SourceKind.video,
      SourceKind.manualNote,
    ]) {
      final thumbnail = await resolver.resolve(itemWith(kind: kind));
      expect(thumbnail, isA<ItemThumbnailNone>());
    }
  });
}

/// Un almacén con disco: da la ruta de cada archivo, y cuenta las lecturas.
class _DiskFileStore extends InMemoryFileStore {
  int reads = 0;

  @override
  Future<String?> localPathOf(String relativePath) async =>
      '/disco/$relativePath';

  @override
  Future<Uint8List?> read(String relativePath) {
    reads++;
    return super.read(relativePath);
  }
}
