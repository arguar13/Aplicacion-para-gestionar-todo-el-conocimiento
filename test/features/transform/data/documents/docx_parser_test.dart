import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_files.dart';

void main() {
  const parser = DocxParser();

  Future<String> markdownOf(
    String body, {
    Map<String, String> parts = const {},
  }) async =>
      (await parser.parseBytes(buildDocx(body: body, parts: parts))).markdown;

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

    test('los parrafos de una celda se separan con <br> (F22)', () async {
      // Un salto de verdad partiria la fila; antes se pegaban con un
      // espacio y no se distinguia donde terminaba cada uno.
      const body = '''
    <w:tbl>
      <w:tr>
        <w:tc>
          <w:p><w:r><w:t>Primero</w:t></w:r></w:p>
          <w:p><w:r><w:t>Segundo</w:t><w:br/><w:t>con salto</w:t></w:r></w:p>
        </w:tc>
        <w:tc><w:p><w:r><w:t>Otra</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
''';

      expect(
        await markdownOf(body),
        '| Primero<br>Segundo<br>con salto | Otra |\n| --- | --- |',
      );
    });

    test('una tabla dentro de una celda no se pierde (F22)', () async {
      // Markdown no tiene tablas anidadas: queda aplanada en su celda, una
      // linea por fila y las celdas separadas por una barra.
      const body = '''
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Zona</w:t></w:r></w:p></w:tc>
        <w:tc>
          <w:p><w:r><w:t>Detalle:</w:t></w:r></w:p>
          <w:tbl>
            <w:tr>
              <w:tc><w:p><w:r><w:t>Norte</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>10</w:t></w:r></w:p></w:tc>
            </w:tr>
            <w:tr>
              <w:tc><w:p><w:r><w:t>Sur</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>20</w:t></w:r></w:p></w:tc>
            </w:tr>
          </w:tbl>
        </w:tc>
      </w:tr>
    </w:tbl>
''';

      expect(
        await markdownOf(body),
        r'| Zona | Detalle:<br>Norte \| 10<br>Sur \| 20 |'
        '\n| --- | --- |',
      );
    });

    test(
      'las filas envueltas en un control de contenido se leen (F22)',
      () async {
        const body = '''
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc></w:tr>
      <w:sdt><w:sdtContent>
        <w:tr><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>
      </w:sdtContent></w:sdt>
    </w:tbl>
''';

        expect(await markdownOf(body), '| A |\n| --- |\n| B |');
      },
    );
  });

  group('lo que no esta en el cuerpo suelto (F22)', () {
    test('un control de contenido se lee en su lugar', () async {
      // Las portadas, los indices y las secciones de una plantilla vienen
      // envueltos en `w:sdt`. Mirando solo `w:p` y `w:tbl` se perdian.
      final markdown = await markdownOf('''
    <w:sdt>
      <w:sdtPr><w:alias w:val="Portada"/></w:sdtPr>
      <w:sdtContent>${wordParagraph('La portada.')}</w:sdtContent>
    </w:sdt>
${wordParagraph('El cuerpo.')}
''');

      expect(markdown, 'La portada.\n\nEl cuerpo.');
    });

    test('un control de contenido dentro de un parrafo tambien', () async {
      const body = '''
    <w:p>
      <w:r><w:t xml:space="preserve">Firma: </w:t></w:r>
      <w:sdt><w:sdtContent><w:r><w:t>Ana Martinez</w:t></w:r></w:sdtContent></w:sdt>
    </w:p>
''';

      expect(await markdownOf(body), 'Firma: Ana Martinez');
    });

    test('el XML personalizado no esconde sus parrafos', () async {
      final markdown = await markdownOf('''
    <w:customXml w:element="resumen">${wordParagraph('Dentro.')}</w:customXml>
''');

      expect(markdown, 'Dentro.');
    });
  });

  group('encabezados y pies de pagina (F22)', () {
    const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rIdH1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
  <Relationship Id="rIdH2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header2.xml"/>
  <Relationship Id="rIdF1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>''';

    final parts = {
      'word/_rels/document.xml.rels': rels,
      'word/header1.xml': wordPart('w:hdr', wordParagraph('Informe anual')),
      'word/header2.xml': wordPart('w:hdr', wordParagraph('Portada aparte')),
      'word/footer1.xml': wordPart('w:ftr', wordParagraph('Empresa S.A.')),
    };

    test('se guardan una vez: el encabezado arriba y el pie abajo, aunque '
        'se repitan en cada seccion', () async {
      const section = '''
<w:sectPr>
  <w:headerReference w:type="default" r:id="rIdH1"/>
  <w:footerReference w:type="default" r:id="rIdF1"/>
</w:sectPr>''';
      final markdown = await markdownOf('''
    <w:p><w:pPr>$section</w:pPr><w:r><w:t>Primera seccion.</w:t></w:r></w:p>
${wordParagraph('Segunda seccion.')}
    $section
''', parts: parts);

      expect(
        markdown,
        'Informe anual\n\n---\n\n'
        'Primera seccion.\n\nSegunda seccion.\n\n---\n\n'
        'Empresa S.A.',
      );
    });

    test('el de primera pagina solo si la seccion lo usa', () async {
      // Word conserva el encabezado de "primera pagina distinta" aunque se
      // haya desactivado: ese no se ve, y no se guarda.
      final sinPrimera = await markdownOf('''
${wordParagraph('Cuerpo.')}
    <w:sectPr>
      <w:headerReference w:type="first" r:id="rIdH2"/>
      <w:headerReference w:type="default" r:id="rIdH1"/>
    </w:sectPr>
''', parts: parts);
      final conPrimera = await markdownOf('''
${wordParagraph('Cuerpo.')}
    <w:sectPr>
      <w:headerReference w:type="first" r:id="rIdH2"/>
      <w:headerReference w:type="default" r:id="rIdH1"/>
      <w:titlePg/>
    </w:sectPr>
''', parts: parts);

      expect(sinPrimera, 'Informe anual\n\n---\n\nCuerpo.');
      expect(conPrimera, 'Portada aparte\n\nInforme anual\n\n---\n\nCuerpo.');
    });
  });

  group('notas y comentarios (F22)', () {
    String footnote(String id, String text, {String? type}) =>
        '''
<w:footnote w:id="$id"${type == null ? '' : ' w:type="$type"'}>
  <w:p>
    <w:r><w:footnoteRef/></w:r>
    <w:r><w:t xml:space="preserve">$text</w:t></w:r>
  </w:p>
</w:footnote>''';

    test(
      'la nota al pie deja su marca en el lugar y su texto al final',
      () async {
        // Los separadores (id -1 y 0) son la raya que Word dibuja arriba de
        // las notas: nadie los nombra y no se guardan. Las marcas se numeran
        // en el orden en que aparecen, no por su id.
        final parts = {
          'word/footnotes.xml': wordPart(
            'w:footnotes',
            footnote('-1', '', type: 'separator') +
                footnote('0', '', type: 'continuationSeparator') +
                footnote('1', ' Primera nota.') +
                footnote('2', ' Segunda nota.'),
          ),
        };

        final markdown = await markdownOf('''
    <w:p>
      <w:r><w:t>Una idea</w:t></w:r>
      <w:r><w:footnoteReference w:id="2"/></w:r>
      <w:r><w:t xml:space="preserve"> y otra</w:t></w:r>
      <w:r><w:footnoteReference w:id="1"/></w:r>
      <w:r><w:t>.</w:t></w:r>
    </w:p>
''', parts: parts);

        expect(
          markdown,
          'Una idea[^1] y otra[^2].\n\n'
          '[^1]: Segunda nota.\n\n'
          '[^2]: Primera nota.',
        );
      },
    );

    test('una nota de dos parrafos sigue con sangria', () async {
      final parts = {
        'word/footnotes.xml': wordPart('w:footnotes', '''
<w:footnote w:id="1">
  <w:p><w:r><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> Primer parrafo.</w:t></w:r></w:p>
  <w:p><w:r><w:t>Segundo parrafo.</w:t></w:r></w:p>
</w:footnote>'''),
      };

      final markdown = await markdownOf('''
    <w:p><w:r><w:t>Texto</w:t></w:r><w:r><w:footnoteReference w:id="1"/></w:r></w:p>
''', parts: parts);

      expect(
        markdown,
        'Texto[^1]\n\n[^1]: Primer parrafo.\n\n    Segundo parrafo.',
      );
    });

    test('las notas finales se marcan como las numera Word: i, ii', () async {
      final parts = {
        'word/endnotes.xml': wordPart(
          'w:endnotes',
          '<w:endnote w:id="1"><w:p><w:r><w:t>La fuente.</w:t></w:r></w:p></w:endnote>',
        ),
      };

      final markdown = await markdownOf('''
    <w:p><w:r><w:t>Dato</w:t></w:r><w:r><w:endnoteReference w:id="1"/></w:r></w:p>
''', parts: parts);

      expect(markdown, 'Dato[^i]\n\n[^i]: La fuente.');
    });

    test('un comentario se guarda con su autor', () async {
      final parts = {
        'word/comments.xml': wordPart('w:comments', '''
<w:comment w:id="0" w:author="Ana">
  <w:p>
    <w:r><w:annotationRef/></w:r>
    <w:r><w:t>Revisar la cifra.</w:t></w:r>
  </w:p>
</w:comment>'''),
      };

      final markdown = await markdownOf('''
    <w:p>
      <w:commentRangeStart w:id="0"/>
      <w:r><w:t>Ventas: 300</w:t></w:r>
      <w:commentRangeEnd w:id="0"/>
      <w:r><w:commentReference w:id="0"/></w:r>
    </w:p>
''', parts: parts);

      expect(markdown, 'Ventas: 300[^c1]\n\n[^c1]: (Ana) Revisar la cifra.');
    });
  });

  group('numeracion real (F22)', () {
    String level(
      int ilvl,
      String format,
      String text, {
      int start = 1,
      String? style,
    }) =>
        '''
<w:lvl w:ilvl="$ilvl">
  <w:start w:val="$start"/>
  <w:numFmt w:val="$format"/>
  <w:lvlText w:val="$text"/>
  ${style == null ? '' : '<w:pStyle w:val="$style"/>'}
</w:lvl>''';

    String numbered(String text, {required int numId, int ilvl = 0}) =>
        '''
<w:p>
  <w:pPr><w:numPr><w:ilvl w:val="$ilvl"/><w:numId w:val="$numId"/></w:numPr></w:pPr>
  <w:r><w:t>$text</w:t></w:r>
</w:p>''';

    test('los numeros y las letras de Word, no guiones', () async {
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  ${level(0, 'decimal', '%1.')}
  ${level(1, 'lowerLetter', '%2)')}
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'''),
      };

      final markdown = await markdownOf(
        numbered('Uno', numId: 1) +
            numbered('Dos', numId: 1) +
            numbered('Dos a', numId: 1, ilvl: 1) +
            numbered('Dos b', numId: 1, ilvl: 1) +
            numbered('Tres', numId: 1) +
            numbered('Tres a', numId: 1, ilvl: 1),
        parts: parts,
      );

      expect(
        markdown,
        '1. Uno\n\n2. Dos\n\n  a) Dos a\n\n  b) Dos b\n\n3. Tres\n\n'
        '  a) Tres a',
      );
    });

    test('la numeracion de varios niveles: 3.2.1', () async {
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  ${level(0, 'decimal', '%1.', start: 3)}
  ${level(1, 'decimal', '%1.%2.', start: 2)}
  ${level(2, 'decimal', '%1.%2.%3')}
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'''),
      };

      final markdown = await markdownOf(
        numbered('Metodo', numId: 1) +
            numbered('Muestra', numId: 1, ilvl: 1) +
            numbered('Criterios', numId: 1, ilvl: 2),
        parts: parts,
      );

      expect(markdown, '3. Metodo\n\n  3.2. Muestra\n\n    3.2.1 Criterios');
    });

    test('una lista que Word reinicia vuelve a empezar', () async {
      // Word escribe "reiniciar en 1" como otra lista con la misma
      // definicion y un `startOverride`. Sin el, la segunda lista continua.
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">${level(0, 'upperRoman', '%1.')}</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="3"><w:abstractNumId w:val="0"/>
  <w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride>
</w:num>'''),
      };

      final markdown = await markdownOf(
        numbered('A', numId: 1) +
            numbered('B', numId: 1) +
            numbered('C', numId: 2) +
            numbered('D', numId: 3),
        parts: parts,
      );

      expect(markdown, 'I. A\n\nII. B\n\nIII. C\n\nI. D');
    });

    test('las vinetas siguen siendo guiones', () async {
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">${level(0, 'bullet', '\uF0B7')}</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'''),
      };

      final markdown = await markdownOf(
        numbered('Suelto', numId: 1),
        parts: parts,
      );

      expect(markdown, '- Suelto');
    });

    test('los titulos numerados por su estilo llevan su numero', () async {
      // Asi numera Word "1. Introduccion", "1.1 Alcance": el numero viene
      // del estilo del titulo, no del parrafo.
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  ${level(0, 'decimal', '%1.', style: 'Heading1')}
  ${level(1, 'decimal', '%1.%2', style: 'Heading2')}
</w:abstractNum>
<w:num w:numId="5"><w:abstractNumId w:val="0"/></w:num>'''),
        'word/styles.xml': wordPart('w:styles', '''
<w:style w:type="paragraph" w:styleId="Heading1">
  <w:pPr><w:numPr><w:numId w:val="5"/></w:numPr><w:outlineLvl w:val="0"/></w:pPr>
</w:style>
<w:style w:type="paragraph" w:styleId="Heading2">
  <w:basedOn w:val="Heading1"/>
  <w:pPr><w:numPr><w:ilvl w:val="1"/></w:numPr></w:pPr>
</w:style>'''),
      };

      final markdown = await markdownOf(
        wordParagraph('Introduccion', style: 'Heading1') +
            wordParagraph('Alcance', style: 'Heading2'),
        parts: parts,
      );

      expect(markdown, '# 1. Introduccion\n\n## 1.1 Alcance');
    });
  });

  group('caracteres especiales (F22)', () {
    test('un simbolo de Symbol sale como su letra', () async {
      // Word guarda el codigo en la fuente: en Symbol, la "a" es una alfa.
      const body = '''
    <w:p>
      <w:r><w:t xml:space="preserve">Angulo </w:t></w:r>
      <w:r><w:sym w:font="Symbol" w:char="F061"/></w:r>
      <w:r><w:t xml:space="preserve"> </w:t></w:r>
      <w:r><w:sym w:font="Symbol" w:char="F0B3"/></w:r>
      <w:r><w:t xml:space="preserve"> 90</w:t></w:r>
      <w:r><w:sym w:font="Symbol" w:char="F0B0"/></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Angulo α ≥ 90°');
    });

    test('un simbolo de otra fuente sale como su caracter', () async {
      const body = '''
    <w:p>
      <w:r><w:sym w:font="Wingdings" w:char="F0FC"/></w:r>
      <w:r><w:t xml:space="preserve"> hecho </w:t></w:r>
      <w:r><w:sym w:font="Cambria Math" w:char="2192"/></w:r>
    </w:p>
''';

      expect(await markdownOf(body), '✔ hecho →');
    });

    test('el guion irrompible y el opcional no se pierden', () async {
      const body = '''
    <w:p>
      <w:r><w:t>e</w:t><w:noBreakHyphen/><w:t xml:space="preserve">mail y ex</w:t><w:softHyphen/><w:t>plicacion</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'e\u2011mail y ex\u00ADplicacion');
    });

    test('el retorno de carro es un salto de linea', () async {
      const body = '''
    <w:p><w:r><w:t>Primera</w:t><w:cr/><w:t>Segunda</w:t></w:r></w:p>
''';

      expect(await markdownOf(body), 'Primera  \nSegunda');
    });

    test('la sangria de adelante es del original y se conserva', () async {
      const body = '''
    <w:p><w:r><w:tab/><w:t>Sangrado con tabulacion.</w:t></w:r></w:p>
    <w:p><w:r><w:t xml:space="preserve">  Con dos espacios.</w:t></w:r></w:p>
''';

      expect(
        await markdownOf(body),
        '\tSangrado con tabulacion.\n\n  Con dos espacios.',
      );
    });

    test('cuatro asteriscos escritos en el texto no se borran', () async {
      // Antes las marcas de negrita se fusionaban borrando todo `****`, y se
      // llevaban puesto el que estaba escrito.
      const body = '''
    <w:p>
      <w:r><w:t xml:space="preserve">Clave: ****</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>Dos</w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve"> pedazos</w:t></w:r>
      <w:r><w:t xml:space="preserve"> y ****.</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Clave: ****\n\n**Dos pedazos** y ****.');
    });
  });

  group('cuadros de texto (F22)', () {
    const cuadro = '''
<w:txbxContent>
  <w:p><w:r><w:t>Primera linea del cuadro.</w:t></w:r></w:p>
  <w:p><w:r><w:t>Segunda linea del cuadro.</w:t></w:r></w:p>
</w:txbxContent>''';

    test('se leen una vez, con sus parrafos separados', () async {
      // Word guarda el cuadro dos veces —para programas nuevos y viejos—
      // dentro de `mc:AlternateContent`. Se leian las dos, y los parrafos
      // del cuadro quedaban pegados entre si y a la frase de afuera.
      const body =
          '''
    <w:p>
      <w:r><w:t>Antes.</w:t></w:r>
      <w:r>
        <mc:AlternateContent>
          <mc:Choice Requires="wps">
            <w:drawing><wp:anchor><a:graphic><a:graphicData>
              <wps:wsp><wps:txbx>$cuadro</wps:txbx></wps:wsp>
            </a:graphicData></a:graphic></wp:anchor></w:drawing>
          </mc:Choice>
          <mc:Fallback>
            <w:pict><v:shape><v:textbox>$cuadro</v:textbox></v:shape></w:pict>
          </mc:Fallback>
        </mc:AlternateContent>
      </w:r>
    </w:p>
''';

      expect(
        await markdownOf(body),
        'Antes.\n\nPrimera linea del cuadro.\n\nSegunda linea del cuadro.',
      );
    });

    test('un cuadro viejo, sin version nueva, tambien se lee', () async {
      const body =
          '''
    <w:p><w:r><w:pict><v:shape><v:textbox>$cuadro</v:textbox></v:shape></w:pict></w:r></w:p>
''';

      expect(
        await markdownOf(body),
        'Primera linea del cuadro.\n\nSegunda linea del cuadro.',
      );
    });
  });

  group('metadatos', () {
    test('el titulo y el autor salen de docProps', () async {
      final result = await parser.parseBytes(
        buildDocx(title: 'La tesis de Ana', author: 'Ana Martinez'),
      );

      expect(result.title, 'La tesis de Ana');
      expect(result.author, 'Ana Martinez');
    });

    test('sin metadatos no inventa nada', () async {
      final result = await parser.parseBytes(buildDocx());

      expect(result.title, isNull);
      expect(result.author, isNull);
    });

    test('unos metadatos vacios cuentan como ausentes', () async {
      // Word escribe la etiqueta vacia cuando nunca se puso un titulo. Un
      // titulo vacio pisaria el provisional y dejaria la fila sin nada.
      final result = await parser.parseBytes(
        buildDocx(title: '', author: '   '),
      );

      expect(result.title, isNull);
      expect(result.author, isNull);
    });
  });

  group('archivos rotos', () {
    test('algo que no es un ZIP lanza en vez de reventar', () {
      final basura = Uint8List.fromList(utf8.encode('esto no es un docx'));

      expect(
        () => parser.parseBytes(basura),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un ZIP sin word/document.xml lanza', () {
      expect(
        () => parser.parseBytes(buildPlainZip()),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });

    test('un XML mal formado lanza', () {
      final roto = buildDocx(body: '<w:p><w:r><w:t>sin cerrar');

      expect(
        () => parser.parseBytes(roto),
        throwsA(isA<UnreadableDocumentException>()),
      );
    });
  });
}
