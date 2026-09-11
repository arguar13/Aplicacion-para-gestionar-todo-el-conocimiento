import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/sample_files.dart';

void main() {
  const parser = DocxParser();

  Future<String> markdownOf(String body) async =>
      (await parser.parse(buildDocx(body: body))).markdown;

  group('que sabe leer', () {
    test('solo DOCX', () {
      expect(parser.canParse(FileFormat.docx), isTrue);
      expect(parser.canParse(FileFormat.pdf), isFalse);
      expect(parser.canParse(FileFormat.epub), isFalse);
    });
  });

  group('parrafos', () {
    test('el texto llega entero', () async {
      final markdown = await markdownOf(
        wordParagraph('La primera idea del documento.'),
      );

      expect(markdown, 'La primera idea del documento.');
    });

    test('los parrafos quedan separados, no pegados', () async {
      // Sin la linea en blanco, Markdown los une en un solo parrafo y el
      // documento pierde su division original.
      final markdown = await markdownOf(
        wordParagraph('Primero.') + wordParagraph('Segundo.'),
      );

      expect(markdown, 'Primero.\n\nSegundo.');
    });

    test('los parrafos vacios no dejan huecos', () async {
      // Word los usa para espaciar. Convertirlos en parrafos vacios de
      // Markdown llenaria el texto de saltos que no dicen nada.
      final markdown = await markdownOf(
        wordParagraph('Primero.') +
            wordParagraph('') +
            wordParagraph('Segundo.'),
      );

      expect(markdown, 'Primero.\n\nSegundo.');
    });
  });

  group('encabezados', () {
    test('un Heading1 se convierte en almohadilla', () async {
      final markdown = await markdownOf(
        wordParagraph('El titulo', style: 'Heading1'),
      );

      expect(markdown, '# El titulo');
    });

    test('los niveles se respetan', () async {
      final markdown = await markdownOf(
        wordParagraph('Uno', style: 'Heading1') +
            wordParagraph('Dos', style: 'Heading2') +
            wordParagraph('Tres', style: 'Heading3'),
      );

      expect(markdown, '# Uno\n\n## Dos\n\n### Tres');
    });

    test('un Word en espanol tambien: el estilo se llama distinto', () async {
      // El identificador del estilo depende del idioma en que se creo el
      // documento. Mirar solo "Heading" dejaria sin encabezados a cualquier
      // documento escrito en espanol.
      final markdown = await markdownOf(
        wordParagraph('El titulo', style: 'Ttulo1'),
      );

      expect(markdown, '# El titulo');
    });

    test('sin estilo reconocible, vale el nivel de esquema', () async {
      // `outlineLvl` es numerico y no depende del idioma. Es el respaldo
      // para los documentos con estilos propios.
      final markdown = await markdownOf(
        wordParagraph('El titulo', style: 'MiEstiloPropio', outlineLevel: 0),
      );

      expect(markdown, '# El titulo');
    });

    test('un nivel de esquema mas profundo cuenta desde cero', () async {
      final markdown = await markdownOf(
        wordParagraph('Subtitulo', outlineLevel: 2),
      );

      expect(markdown, '### Subtitulo');
    });
  });

  group('listas', () {
    test('un punto de lista se convierte en guion', () async {
      final markdown = await markdownOf(
        wordParagraph('Lo primero', listLevel: 0),
      );

      expect(markdown, '- Lo primero');
    });

    test('las listas anidadas conservan su sangria', () async {
      final markdown = await markdownOf(
        wordParagraph('Principal', listLevel: 0) +
            wordParagraph('Anidado', listLevel: 1),
      );

      expect(markdown, '- Principal\n\n  - Anidado');
    });
  });

  group('negritas y cursivas', () {
    test('la negrita se marca', () async {
      final markdown = await markdownOf(
        wordParagraph('importante', bold: true),
      );

      expect(markdown, '**importante**');
    });

    test('la cursiva tambien', () async {
      final markdown = await markdownOf(wordParagraph('enfasis', italic: true));

      expect(markdown, '*enfasis*');
    });

    test('las dos juntas se anidan', () async {
      final markdown = await markdownOf(
        wordParagraph('las dos', bold: true, italic: true),
      );

      expect(markdown, '***las dos***');
    });

    test('el atributo desactivado a mano NO pone negrita', () async {
      // En OOXML `<w:b w:val="0"/>` significa desactivado. Mirar solo si la
      // etiqueta existe pondria en negrita justo lo que el usuario quito.
      const body = '''
    <w:p>
      <w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>normal</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'normal');
    });

    test('los espacios quedan afuera de las marcas', () async {
      // `** texto **` no es negrita en Markdown: es un asterisco literal.
      const body = '''
    <w:p>
      <w:r><w:t xml:space="preserve">Antes </w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">medio </w:t></w:r>
      <w:r><w:t>despues</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Antes **medio** despues');
    });

    test(
      'una frase partida en pedazos no sale asteriscada a pedazos',
      () async {
        // Word parte el texto cada vez que cambia algo, incluso una correccion
        // ortografica. Sin fusionar, se veria como asteriscos sueltos en medio
        // de la frase y rompe el resaltado en varios editores.
        const body = '''
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>Una</w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t>frase</w:t></w:r>
    </w:p>
''';

        expect(await markdownOf(body), '**Unafrase**');
      },
    );
  });

  group('saltos y tabulaciones', () {
    test('un salto de linea no abre parrafo nuevo', () async {
      const body = '''
    <w:p>
      <w:r><w:t>Primera</w:t><w:br/><w:t>Segunda</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Primera  \nSegunda');
    });
  });

  group('tablas', () {
    test('una tabla se convierte en tabla de Markdown', () async {
      // Un cuadro comparativo aplastado a texto corrido pierde exactamente la
      // informacion por la que era un cuadro.
      final markdown = await markdownOf(
        wordTable([
          ['Concepto', 'Valor'],
          ['Uno', '1'],
          ['Dos', '2'],
        ]),
      );

      expect(
        markdown,
        '| Concepto | Valor |\n'
        '| --- | --- |\n'
        '| Uno | 1 |\n'
        '| Dos | 2 |',
      );
    });

    test('una fila corta se rellena para no romper la tabla', () async {
      final markdown = await markdownOf(
        wordTable([
          ['A', 'B', 'C'],
          ['solo una'],
        ]),
      );

      expect(markdown, contains('| solo una |  |  |'));
    });

    test('una barra dentro de una celda se escapa', () async {
      // Sin escapar, parte la fila en dos columnas de mas.
      final markdown = await markdownOf(
        wordTable([
          ['a|b', 'c'],
        ]),
      );

      expect(markdown, contains(r'| a\|b | c |'));
    });
  });

  group('metadatos', () {
    test('el titulo y el autor salen de docProps', () async {
      final result = await parser.parse(
        buildDocx(title: 'La tesis de Ana', author: 'Ana Martinez'),
      );

      expect(result.title, 'La tesis de Ana');
      expect(result.author, 'Ana Martinez');
    });

    test('sin metadatos no inventa nada', () async {
      final result = await parser.parse(buildDocx());

      expect(result.title, isNull);
      expect(result.author, isNull);
    });

    test('unos metadatos vacios cuentan como ausentes', () async {
      // Word escribe la etiqueta vacia cuando nunca se puso un titulo. Un
      // titulo vacio pisaria el provisional y dejaria la fila sin nada.
      final result = await parser.parse(buildDocx(title: '', author: '   '));

      expect(result.title, isNull);
      expect(result.author, isNull);
    });
  });

  group('archivos rotos', () {
    test('algo que no es un ZIP lanza en vez de reventar', () {
      final basura = Uint8List.fromList(utf8.encode('esto no es un docx'));

      expect(
        () => parser.parse(basura),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un ZIP sin word/document.xml lanza', () {
      expect(
        () => parser.parse(buildPlainZip()),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un XML mal formado lanza', () {
      final roto = buildDocx(body: '<w:p><w:r><w:t>sin cerrar');

      expect(
        () => parser.parse(roto),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });
  });
}
