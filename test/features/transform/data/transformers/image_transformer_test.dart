import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/transform/data/transformers/image_transformer.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fake_image_text_extractor.dart';
import '../../../../support/in_memory_file_store.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late InMemoryFileStore files;
  late FakeImageTextExtractor extractor;
  late ImageTransformer transformer;

  setUp(() {
    files = InMemoryFileStore();
    extractor = FakeImageTextExtractor();
    transformer = ImageTransformer(
      extractor: extractor,
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
    );
  });

  Future<KnowledgeItem> seed({
    SourceKind kind = SourceKind.image,
    bool withFile = true,
  }) async {
    final path = withFile
        ? await files.save(
            bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
            suggestedName: 'foto.jpg',
            id: 'src-1',
          )
        : null;

    return KnowledgeItem(
      id: 'item-1',
      title: 'Foto',
      source: Source(
        id: 'src-1',
        kind: kind,
        capturedAt: now,
        originalFilePath: path,
      ),
      processingState: ProcessingState.pending,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('a qué se aplica', () {
    test('a una imagen con archivo y sin contenido', () async {
      expect(transformer.canTransform(await seed()), isTrue);
    });

    test('NO a algo que no es una imagen', () async {
      final item = await seed(kind: SourceKind.document);

      expect(transformer.canTransform(item), isFalse);
    });

    test('NO a una imagen sin archivo guardado', () async {
      final item = await seed(withFile: false);

      expect(transformer.canTransform(item), isFalse);
    });

    test('NO a una que ya se reconoció', () async {
      // Sin esto, cada pasada de la cola repetiría el mismo reconocimiento
      // sobre la misma imagen.
      extractor.text = 'un cartel';
      final item = await seed();
      final reconocida = await transformer.transform(item);

      expect(transformer.canTransform(reconocida), isFalse);
    });
  });

  group('lo que guarda', () {
    test('el texto reconocido queda como contenido buscable', () async {
      extractor.text = 'Horario de atención: 9 a 18';
      final item = await seed();

      final result = await transformer.transform(item);

      expect(result.renditions, hasLength(1));
      expect(result.renditions.single.kind, RenditionKind.plainText);
      expect(result.searchableText, contains('Horario de atención'));
    });

    test('sin texto reconocido, el elemento queda igual', () async {
      // La mayoría de las fotos no tienen ninguna letra adentro, y eso está
      // bien: no es un error, es el caso normal.
      final item = await seed();

      expect(await transformer.transform(item), item);
    });

    test('se le pide reconocer la ruta absoluta, no la relativa que guarda '
        'la base', () async {
      final item = await seed();

      await transformer.transform(item);

      expect(extractor.requested.single, startsWith('/memoria/'));
      expect(extractor.requested.single, isNot(item.source.originalFilePath));
    });

    test('si el archivo ya no está, lo dice con claridad', () async {
      // Alguien vació el almacenamiento de la app desde los ajustes del
      // sistema. Es distinto de una imagen corrupta y conviene distinguirlo.
      final item = await seed();
      await files.delete(item.source.originalFilePath!);

      expect(
        () => transformer.transform(item),
        throwsA(isA<MissingOriginalFileException>()),
      );
    });
  });
}
