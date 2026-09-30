import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/epub_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_files.dart';
import '../../../../support/silent_logger.dart';

/// Un registro que se queda con los avisos, para ver que algo se registró.
class _RecordingLogger extends SilentLogger {
  final warnings = <String>[];

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      warnings.add(message);
}

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
      // El conversor de antes, html2md, escribia por defecto los de nivel 1 y
      // 2 subrayados y del 3 en adelante con almohadillas: un mismo libro
      // saldria con dos convenciones mezcladas. Queda como regresion.
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

  // Cada defecto del inventario de F22, con el texto guardado comparado
  // entero, carácter por carácter.
  group('fidelidad (F22)', () {
    test('el libro entero sale exactamente así', () async {
      final result = await parser.parseBytes(buildEpub());

      expect(
        result.markdown,
        '# Primero\n\nEl primer capítulo.\n\n---\n\n'
        '# Segundo\n\nEl segundo capítulo.',
      );
    });

    test('el título interno, el CSS y el JavaScript del capítulo no se '
        'vuelcan como texto', () async {
      // html2md convertía el documento entero, <head> incluido: cada
      // capítulo empezaba con su título interno pegado a las reglas de CSS.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [(name: 'c.xhtml', html: '<p>El texto.</p>')],
          head: [
            '<title>Capítulo interno</title>',
            '<style>p { color: red }</style>',
            '<script>var x = 1;</script>',
          ].join(),
        ),
      );

      expect(result.markdown, 'El texto.');
    });

    test('un <title/> vacío en el head no se come el capítulo', () async {
      // Leído como HTML, el título vacío no se cerraba nunca y el capítulo
      // entero quedaba adentro: se perdía.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [(name: 'c.xhtml', html: '<p>El texto.</p>')],
          head: '<title/>',
        ),
      );

      expect(result.markdown, 'El texto.');
    });

    test('no agrega barras invertidas', () async {
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (
              name: 'c.xhtml',
              html: '<p>Ver [1].</p><p>1. Intro</p><p>a_b_c</p>',
            ),
          ],
        ),
      );

      expect(result.markdown, 'Ver [1].\n\n1. Intro\n\na_b_c');
    });

    test('los superíndices quedan marcados, no pegados', () async {
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [(name: 'c.xhtml', html: '<p>10<sup>6</sup></p>')],
        ),
      );

      expect(result.markdown, '10<sup>6</sup>');
    });

    test('un capítulo en UTF-16 se lee entero', () async {
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [(name: 'c.xhtml', html: '<p>Año, niño y café.</p>')],
          utf16: {'c.xhtml'},
        ),
      );

      expect(result.markdown, 'Año, niño y café.');
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

    test('el material no lineal va al final, no se pierde (F22)', () async {
      // Antes se descartaba: con él se iban las notas al final y los
      // apéndices de libros enteros. Va después de lo lineal para no
      // interrumpir la lectura, en el orden del spine.
      final result = await parser.parseBytes(
        buildEpub(
          chapters: const [
            (name: 'notas.xhtml', html: '<p>Las notas</p>'),
            (name: 'cap.xhtml', html: '<p>El libro de verdad</p>'),
            (name: 'apendice.xhtml', html: '<p>El apéndice</p>'),
          ],
          nonLinear: {'notas.xhtml', 'apendice.xhtml'},
        ),
      );

      expect(
        result.markdown,
        'El libro de verdad\n\n---\n\nLas notas\n\n---\n\nEl apéndice',
      );
      expect(result.pageCount, 3);
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

    test('un capitulo que falta no se saltea en silencio: queda registrado '
        '(F22)', () async {
      final logger = _RecordingLogger();

      final result = await EpubParser(
        logger: logger,
      ).parseBytes(buildEpub(missingFiles: {'cap2.xhtml'}));

      expect(result.markdown, '# Primero\n\nEl primer capítulo.');
      expect(logger.warnings.single, contains('cap2.xhtml'));
    });
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
