import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_files.dart';

void main() {
  const parser = EpubParser();

  group('que sabe leer', () {
    test('solo EPUB', () {
      expect(parser.canParse(FileFormat.epub), isTrue);
      expect(parser.canParse(FileFormat.docx), isFalse);
      expect(parser.canParse(FileFormat.pdf), isFalse);
    });
  });

  group('el contenido', () {
    test('el texto de los capitulos llega entero', () async {
      final result = await parser.parseBytes(buildEpub());

      expect(result.markdown, contains('El primer capítulo'));
      expect(result.markdown, contains('El segundo capítulo'));
    });

    test('el XHTML se convierte a Markdown, no se guarda crudo', () async {
      final result = await parser.parseBytes(buildEpub());

      expect(result.markdown, contains('# Primero'));
      expect(result.markdown, isNot(contains('<h1>')));
    });

    test('los encabezados usan almohadillas en todos los niveles', () async {
      // Por defecto la libreria escribe los de nivel 1 y 2 subrayados y del 3
      // en adelante con almohadillas: un mismo libro saldria con dos
      // convenciones mezcladas.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (name: 'c.xhtml', html: '<h1>Uno</h1><h2>Dos</h2><h3>Tres</h3>'),
          ],
        ),
      );

      expect(result.markdown, contains('# Uno'));
      expect(result.markdown, contains('## Dos'));
      expect(result.markdown, contains('### Tres'));
      expect(result.markdown, isNot(contains('---\n')));
    });

    test('los capitulos quedan separados entre si', () async {
      final result = await parser.parseBytes(buildEpub());

      expect(result.markdown, contains('\n\n---\n\n'));
    });

    test('cuenta cuantos capitulos tenia', () async {
      final result = await parser.parseBytes(buildEpub());

      expect(result.pageCount, 2);
    });
  });

  group('el orden de lectura', () {
    test('sale del spine, no del orden del ZIP', () async {
      // Dentro del archivo los capitulos pueden estar en cualquier orden y
      // con cualquier nombre. El spine es la unica lista que garantiza que el
      // capitulo tres vaya despues del dos.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (name: 'zzz.xhtml', html: '<p>Va primero</p>'),
            (name: 'aaa.xhtml', html: '<p>Va segundo</p>'),
          ],
        ),
      );

      expect(
        result.markdown.indexOf('Va primero'),
        lessThan(result.markdown.indexOf('Va segundo')),
      );
    });

    test('el material auxiliar marcado como no lineal queda afuera', () async {
      // Notas de la editorial, publicidad: no forman parte del hilo de
      // lectura, e incluirlas mezclaria el texto del libro con el que no lo
      // es.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (name: 'cap.xhtml', html: '<p>El libro de verdad</p>'),
            (name: 'aviso.xhtml', html: '<p>Publicidad de la editorial</p>'),
          ],
          nonLinear: {'aviso.xhtml'},
        ),
      );

      expect(result.markdown, contains('El libro de verdad'));
      expect(result.markdown, isNot(contains('Publicidad')));
    });

    test(
      'un spine que apunta a un capitulo inexistente no rompe el resto',
      () async {
        // Pasa en libros mal armados. Perder el libro entero por una linea
        // sobrante del indice seria desproporcionado.
        final result = await parser.parseBytes(
          buildEpub(withDanglingSpineEntry: true),
        );

        expect(result.markdown, contains('El primer capítulo'));
        expect(result.pageCount, 2);
      },
    );
  });

  group('donde esta cada cosa', () {
    test(
      'el OPF se busca donde diga el contenedor, no donde se supone',
      () async {
        // Lo unico fijo en un EPUB es META-INF/container.xml. Dar por sentado
        // OEBPS/content.opf funcionaria con casi todos los libros y fallaria en
        // silencio con el resto.
        final result = await parser.parseBytes(
          buildEpub(containerPath: 'libro/paquete.opf'),
        );

        expect(result.markdown, contains('El primer capítulo'));
      },
    );

    test('un OPF en la raiz tambien funciona', () async {
      final result = await parser.parseBytes(
        buildEpub(containerPath: 'libro.opf'),
      );

      expect(result.markdown, contains('El primer capítulo'));
    });

    test('un capitulo con acentos en el nombre se encuentra igual', () async {
      // Las rutas del manifiesto son URL: `El nino.xhtml` aparece escapado y
      // no encontraria su archivo sin desescaparlo.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (name: 'El nino y la mar.xhtml', html: '<p>Con espacios</p>'),
          ],
        ),
      );

      expect(result.markdown, contains('Con espacios'));
    });
  });

  group('metadatos', () {
    test('el titulo y el autor salen del OPF', () async {
      final result = await parser.parseBytes(
        buildEpub(title: 'Cien anos de soledad', author: 'Gabriel Garcia'),
      );

      expect(result.title, 'Cien anos de soledad');
      expect(result.author, 'Gabriel Garcia');
    });

    test('unos metadatos vacios cuentan como ausentes', () async {
      final result = await parser.parseBytes(
        buildEpub(title: '', author: '  '),
      );

      expect(result.title, isNull);
      expect(result.author, isNull);
    });
  });

  group('libros rotos', () {
    test('algo que no es un ZIP lanza', () {
      final basura = Uint8List.fromList(utf8.encode('esto no es un epub'));

      expect(
        () => parser.parseBytes(basura),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un ZIP sin META-INF/container.xml lanza', () {
      expect(
        () => parser.parseBytes(buildPlainZip()),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un libro sin un solo capitulo legible lanza', () {
      expect(
        () => parser.parseBytes(buildEpub(chapters: const [])),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });
  });
}
