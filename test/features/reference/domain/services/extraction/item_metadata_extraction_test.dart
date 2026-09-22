import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/reference/domain/services/extraction/item_metadata_extraction.dart';

import '../../../../../support/in_memory_file_store.dart';

void main() {
  final now = DateTime(2026, 9, 20, 10);
  late InMemoryFileStore files;

  setUp(() => files = InMemoryFileStore());

  KnowledgeItem item(Source source) => KnowledgeItem(
    id: 'item-1',
    title: 'Un elemento',
    source: source,
    processingState: ProcessingState.ready,
    createdAt: now,
    updatedAt: now,
  );

  group('YouTube', () {
    test('lee el canal y la fecha directo de la fuente, sin archivo', () async {
      final source = Source(
        id: 'src-1',
        kind: SourceKind.youtube,
        capturedAt: now,
        authorName: 'Canal de Prueba',
        publishedAt: DateTime(2021),
      );

      final extracted = await extractedMetadataOf(item(source), files);

      expect(extracted, isNotNull);
      expect(
        extracted!.reference.contributors.single.name.label,
        'Canal de Prueba',
      );
    });
  });

  group('document', () {
    test('un PDF con Info se lee', () async {
      final bytes = Uint8List.fromList(
        latin1.encode(
          '%PDF-1.4\n1 0 obj\n<< /Title (Un titulo) >>\nendobj\n'
          'trailer\n<< /Root 1 0 R /Info 1 0 R >>\n%%EOF\n',
        ),
      );
      final path = await files.save(
        bytes: bytes,
        suggestedName: 'a.pdf',
        id: 'src-1',
      );
      final source = Source(
        id: 'src-1',
        kind: SourceKind.document,
        capturedAt: now,
        originalFilePath: path,
      );

      final extracted = await extractedMetadataOf(item(source), files);

      expect(extracted?.title, 'Un titulo');
    });

    test('un DOCX —no PDF— no se lee: ya trae su propio titulo', () async {
      final bytes = Uint8List.fromList(utf8.encode('PK\u0003\u0004basura'));
      final path = await files.save(
        bytes: bytes,
        suggestedName: 'a.docx',
        id: 'src-1',
      );
      final source = Source(
        id: 'src-1',
        kind: SourceKind.document,
        capturedAt: now,
        originalFilePath: path,
      );

      expect(await extractedMetadataOf(item(source), files), isNull);
    });

    test('sin ruta de archivo, no hay nada que leer', () async {
      final source = Source(
        id: 'src-1',
        kind: SourceKind.document,
        capturedAt: now,
      );

      expect(await extractedMetadataOf(item(source), files), isNull);
    });

    test(
      'con ruta pero sin archivo en el almacén, no hay nada que leer',
      () async {
        final source = Source(
          id: 'src-1',
          kind: SourceKind.document,
          capturedAt: now,
          originalFilePath: 'no-existe.pdf',
        );

        expect(await extractedMetadataOf(item(source), files), isNull);
      },
    );
  });

  group('webPage', () {
    test('una pagina archivada se lee', () async {
      const html = '''
<html><head><meta name="citation_title" content="Un articulo"></head></html>
''';
      final path = await files.save(
        bytes: Uint8List.fromList(utf8.encode(html)),
        suggestedName: 'pagina.html',
        id: 'src-1',
      );
      final source = Source(
        id: 'src-1',
        kind: SourceKind.webPage,
        capturedAt: now,
        originalFilePath: path,
      );

      final extracted = await extractedMetadataOf(item(source), files);

      expect(extracted?.title, 'Un articulo');
    });

    test('sin pagina archivada, no hay nada que leer', () async {
      final source = Source(
        id: 'src-1',
        kind: SourceKind.webPage,
        capturedAt: now,
      );

      expect(await extractedMetadataOf(item(source), files), isNull);
    });
  });

  group('lo que nunca se lee', () {
    test(
      'una nota, una imagen, un audio y un video no tienen lector',
      () async {
        for (final kind in [
          SourceKind.manualNote,
          SourceKind.image,
          SourceKind.audio,
          SourceKind.video,
          SourceKind.socialPost,
          SourceKind.reference,
        ]) {
          final source = Source(id: 'src-1', kind: kind, capturedAt: now);
          expect(await extractedMetadataOf(item(source), files), isNull);
        }
      },
    );
  });
}
