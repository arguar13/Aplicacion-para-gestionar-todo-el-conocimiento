import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';
import 'package:sinapsis/features/transform/data/transformers/document_transformer.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/in_memory_file_store.dart';
import '../../../../support/sample_files.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);
  late InMemoryFileStore files;
  late DocumentTransformer transformer;

  setUp(() {
    files = InMemoryFileStore();
    transformer = DocumentTransformer(
      parsers: const [DocxParser(), EpubParser(), PlainTextParser()],
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
    );
  });

  /// Guarda un archivo y devuelve el elemento que lo referencia, como lo
  /// dejaria el adaptador de archivos.
  Future<KnowledgeItem> seed(
    Uint8List bytes, {
    String name = 'apunte.docx',
    SourceKind kind = SourceKind.document,
    String title = 'Apunte',
  }) async {
    final path = await files.save(
      bytes: bytes,
      suggestedName: name,
      id: 'src-1',
    );

    return KnowledgeItem(
      id: 'item-1',
      title: title,
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

  group('a que se aplica', () {
    test('a un documento con archivo y sin contenido', () async {
      expect(transformer.canTransform(await seed(buildDocx())), isTrue);
    });

    test('NO a algo que no es un documento', () async {
      final item = await seed(buildDocx(), kind: SourceKind.webPage);

      expect(transformer.canTransform(item), isFalse);
    });

    test('NO a un documento sin archivo guardado', () async {
      final item = await seed(buildDocx());
      final sinArchivo = item.copyWith(
        source: item.source.copyWith(originalFilePath: null),
      );

      expect(transformer.canTransform(sinArchivo), isFalse);
    });

    test('NO a uno que ya se leyo', () async {
      // Sin esto, cada pasada de la cola volveria a parsear el mismo PDF de
      // mil paginas.
      final item = await seed(buildDocx());
      final leido = await transformer.transform(item);

      expect(transformer.canTransform(leido), isFalse);
    });
  });

  group('lo que guarda', () {
    test('el texto del documento queda como contenido buscable', () async {
      final item = await seed(
        buildDocx(body: wordParagraph('La idea central del informe.')),
      );

      final result = await transformer.transform(item);

      expect(result.renditions, hasLength(1));
      expect(result.renditions.single.kind, RenditionKind.markdown);
      expect(result.searchableText, contains('La idea central del informe'));
    });

    test('el titulo del documento gana sobre el del archivo', () async {
      // Un PDF llamado "descarga (3).pdf" puede tener un titulo de verdad
      // adentro.
      final item = await seed(
        buildDocx(title: 'La tesis de Ana'),
        title: 'Descarga (3)',
      );

      final result = await transformer.transform(item);

      expect(result.title, 'La tesis de Ana');
    });

    test('sin titulo adentro, se conserva el provisional', () async {
      final item = await seed(buildDocx(), title: 'Apuntes de clase');

      final result = await transformer.transform(item);

      expect(result.title, 'Apuntes de clase');
    });

    test('el autor del documento completa la procedencia', () async {
      final item = await seed(buildDocx(author: 'Ana Martinez'));

      final result = await transformer.transform(item);

      expect(result.source.authorName, 'Ana Martinez');
    });

    test('un libro en EPUB se lee, con su titulo y su autor', () async {
      final item = await seed(
        buildEpub(title: 'Cien anos de soledad', author: 'Gabriel Garcia'),
        name: 'libro.epub',
        title: 'Libro',
      );

      final result = await transformer.transform(item);

      expect(result.title, 'Cien anos de soledad');
      expect(result.source.authorName, 'Gabriel Garcia');
      expect(result.searchableText, contains('El primer capítulo'));
    });

    test('un archivo de texto suelto tambien se lee', () async {
      final item = await seed(
        Uint8List.fromList(utf8.encode('Unas notas sueltas que escribi.')),
        name: 'notas.txt',
      );

      final result = await transformer.transform(item);

      expect(result.searchableText, contains('notas sueltas'));
    });

    test(
      'de un Markdown sale ademas el titulo de su primer encabezado',
      () async {
        final item = await seed(
          Uint8List.fromList(
            utf8.encode('# La idea buena\n\nY el desarrollo.'),
          ),
          name: 'idea.md',
          title: 'Idea',
        );

        final result = await transformer.transform(item);

        expect(result.title, 'La idea buena');
      },
    );
  });

  group('lo que no se puede leer', () {
    test('un formato sin lector se deja como esta, sin fallar', () async {
      // Un fallo pondria el elemento en rojo y ofreceria reintentar algo que
      // nunca va a funcionar. No paso nada malo: el archivo esta guardado.
      final item = await seed(buildPlainZip(), name: 'cosas.zip');

      final result = await transformer.transform(item);

      expect(result, item);
      expect(result.renditions, isEmpty);
    });

    test(
      'un documento vacio no deja una forma de contenido en blanco',
      () async {
        // Una fila que dice "contenido" y esta vacia es peor que ninguna: en el
        // detalle se ve un panel vacio en vez del aviso de que falta el texto.
        final item = await seed(buildDocx(body: wordParagraph('   ')));

        final result = await transformer.transform(item);

        expect(result.renditions, isEmpty);
      },
    );

    test('un DOCX con el XML roto lanza, para que quede marcado', () async {
      // Esto si es un fallo de verdad: el archivo es un DOCX —trae su
      // word/document.xml— pero el contenido esta corrupto. El usuario merece
      // verlo en rojo en vez de creer que su documento no tenia texto.
      final item = await seed(buildDocx(body: '<w:p><w:r><w:t>sin cerrar'));

      expect(
        () => transformer.transform(item),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un ZIP cortado no se confunde con un DOCX roto', () async {
      // No llega a reconocerse como DOCX, asi que no hay nada que leer y
      // tampoco hay un fallo que mostrar: el archivo esta guardado.
      final item = await seed(
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]),
        name: 'roto.docx',
      );

      expect(await transformer.transform(item), item);
    });

    test('si el archivo ya no esta, lo dice con claridad', () async {
      // Alguien vacio el almacenamiento de la app desde los ajustes del
      // sistema. Es distinto de un archivo corrupto y conviene distinguirlo.
      final item = await seed(buildDocx());
      await files.delete(item.source.originalFilePath!);

      expect(
        () => transformer.transform(item),
        throwsA(isA<MissingOriginalFileException>()),
      );
    });
  });

  group('cuando la referencia ya esta confirmada (F15)', () {
    DocumentTransformer withGuard(Future<bool> Function(String) guard) =>
        DocumentTransformer(
          parsers: const [DocxParser(), EpubParser(), PlainTextParser()],
          files: files,
          ids: FakeIdGenerator(),
          clock: () => now,
          hasConfirmedReference: guard,
        );

    test('no pisa el titulo ni el autor que el documento trae', () async {
      final item = await seed(
        buildDocx(title: 'La tesis de Ana', author: 'Ana Martinez'),
      );

      final result = await withGuard((_) async => true).transform(item);

      expect(result.title, 'Apunte');
      expect(result.source.authorName, isNull);
      // El texto se sigue leyendo igual: solo el titulo y el autor se
      // protegen.
      expect(result.renditions, hasLength(1));
    });

    test('sin nada confirmado, se comporta como siempre', () async {
      final item = await seed(
        buildDocx(title: 'La tesis de Ana', author: 'Ana Martinez'),
      );

      final result = await withGuard((_) async => false).transform(item);

      expect(result.title, 'La tesis de Ana');
      expect(result.source.authorName, 'Ana Martinez');
    });

    test('se pregunta por el id del elemento que se transforma', () async {
      String? asked;
      final item = await seed(buildDocx());

      await withGuard((itemId) async {
        asked = itemId;
        return false;
      }).transform(item);

      expect(asked, item.id);
    });
  });

  test('le pasa el documento al lector sin traerlo a memoria: nombre, '
      'tamaño y cómo leerlo, y el lector decide (F21)', () async {
    final pdf = buildPdf(pageTexts: ['Hola']);
    final parser = _RecordingParser();
    final item = await seed(pdf, name: 'libro.pdf');

    await DocumentTransformer(
      parsers: [parser],
      files: files,
      ids: FakeIdGenerator(),
      clock: () => now,
    ).transform(item);

    final received = parser.received!;
    expect(received.name, 'libro.pdf');
    expect(received.size, pdf.length);
    expect(await received.readRange(0, 5), pdf.sublist(0, 5));
    // En memoria no hay disco del que abrirlo.
    expect(received.localPath, isNull);
  });
}

/// Un lector de PDF que solo anota qué recibió.
class _RecordingParser implements DocumentParser {
  DocumentSource? received;

  @override
  bool canParse(FileFormat format) => format == FileFormat.pdf;

  @override
  Future<ParsedDocument> parse(DocumentSource source) async {
    received = source;
    return const ParsedDocument(markdown: 'Hola');
  }
}
