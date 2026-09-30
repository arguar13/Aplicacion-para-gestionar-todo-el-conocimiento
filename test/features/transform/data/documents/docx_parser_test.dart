import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/features/transform/data/documents/docx_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

import '../../../../support/document_parsing.dart';
import '../../../../support/sample_files.dart';
import '../../../../support/silent_logger.dart';

class _RecordingLogger extends SilentLogger {
  final warnings = <String>[];

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      warnings.add(message);
}

/// Un archivo de relaciones con estas relaciones: `(id, tipo, destino)`. El
/// tipo es el ultimo tramo de la direccion (`numbering`, `chart`...).
String _relationships(List<(String, String, String)> relations) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (final (id, type, target) in relations) '  <Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/$type" Target="$target"/>'].join('\n')}
</Relationships>''';

/// El ZIP [zip] con los datos comprimidos de la parte [name] rotos: como un
/// archivo danado en la descarga o en el disco.
Uint8List _withDamagedPart(Uint8List zip, String name) {
  final nameBytes = utf8.encode(name);
  for (var i = 0; i + 30 < zip.length; i++) {
    final isLocalHeader =
        zip[i] == 0x50 &&
        zip[i + 1] == 0x4B &&
        zip[i + 2] == 0x03 &&
        zip[i + 3] == 0x04;
    if (!isLocalHeader) continue;
    final nameLength = zip[i + 26] | (zip[i + 27] << 8);
    final extraLength = zip[i + 28] | (zip[i + 29] << 8);
    final found = String.fromCharCodes(
      zip.sublist(i + 30, i + 30 + nameLength),
    );
    if (found != String.fromCharCodes(nameBytes)) continue;

    final size =
        zip[i + 18] |
        (zip[i + 19] << 8) |
        (zip[i + 20] << 16) |
        (zip[i + 21] << 24);
    final start = i + 30 + nameLength + extraLength;
    final damaged = Uint8List.fromList(zip);
    // Un bloque de tipo 3 no existe en deflate: el descompresor no puede
    // seguir.
    for (var k = start; k < start + size; k++) {
      damaged[k] = 0xFF;
    }
    return damaged;
  }
  throw StateError('$name no esta en el ZIP');
}

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

  group('ecuaciones (F22)', () {
    String run(String text) => '<m:r><m:t>$text</m:t></m:r>';

    test('un parrafo que es solo una ecuacion no desaparece', () async {
      // Antes todo lo que no era `w:` se descartaba, y la ecuacion con el.
      final markdown = await markdownOf('''
    <w:p><m:oMathPara><m:oMath>
      <m:sSup><m:e>${run('x')}</m:e><m:sup>${run('2')}</m:sup></m:sSup>
      ${run('+')}
      <m:f><m:num>${run('a+b')}</m:num><m:den>${run('c')}</m:den></m:f>
    </m:oMath></m:oMathPara></w:p>
''');

      expect(markdown, 'x^2+(a+b)/c');
    });

    test('una ecuacion en medio de la frase queda en su lugar', () async {
      final markdown = await markdownOf('''
    <w:p>
      <w:r><w:t xml:space="preserve">El area es </w:t></w:r>
      <m:oMath>${run('π')}<m:sSup><m:e>${run('r')}</m:e><m:sup>${run('2')}</m:sup></m:sSup></m:oMath>
      <w:r><w:t>.</w:t></w:r>
    </w:p>
''');

      expect(markdown, 'El area es πr^2.');
    });

    test('sumas, raices, delimitadores e indices', () async {
      final markdown = await markdownOf('''
    <w:p><m:oMathPara>
      <m:oMath>
        <m:nary>
          <m:naryPr><m:chr m:val="∑"/></m:naryPr>
          <m:sub>${run('i=1')}</m:sub><m:sup>${run('n')}</m:sup>
          <m:e><m:sSub><m:e>${run('a')}</m:e><m:sub>${run('i')}</m:sub></m:sSub></m:e>
        </m:nary>
      </m:oMath>
      <m:oMath>
        <m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/><m:e>${run('x+1')}</m:e></m:rad>
        ${run('·')}
        <m:rad><m:deg>${run('3')}</m:deg><m:e>${run('y')}</m:e></m:rad>
      </m:oMath>
      <m:oMath>
        <m:sSup><m:e>${run('x')}</m:e><m:sup>${run('n+1')}</m:sup></m:sSup>
        ${run('∈')}
        <m:d><m:dPr><m:begChr m:val="["/><m:endChr m:val="]"/><m:sepChr m:val=","/></m:dPr>
          <m:e>${run('0')}</m:e><m:e>${run('1')}</m:e>
        </m:d>
      </m:oMath>
      <m:oMath>
        <m:nary><m:sub>${run('0')}</m:sub><m:sup>${run('1')}</m:sup><m:e>${run('f(t)dt')}</m:e></m:nary>
      </m:oMath>
    </m:oMathPara></w:p>
''');

      expect(
        markdown,
        '∑_(i=1)^n a_i  \n'
        '√(x+1)·∛y  \n'
        'x^(n+1)∈[0,1]  \n'
        '∫_0^1 f(t)dt',
      );
    });
  });

  group('campos (F22)', () {
    String field(String type) =>
        '<w:r><w:fldChar w:fldCharType="$type"/></w:r>';
    String code(String text) =>
        '<w:r><w:instrText xml:space="preserve">$text</w:instrText></w:r>';
    String text(String value) =>
        '<w:r><w:t xml:space="preserve">$value</w:t></w:r>';

    test('un campo dentro del codigo de otro no se escribe', () async {
      // `{ IF { MERGEFIELD Sexo } = "F" "Estimada" "Estimado" }`: el "F" es
      // el resultado del campo de adentro, pero esta en el codigo del de
      // afuera. Antes salia "FEstimada".
      final markdown = await markdownOf('''
    <w:p>
      ${field('begin')}${code(' IF ')}
      ${field('begin')}${code(' MERGEFIELD Sexo ')}${field('separate')}${text('F')}${field('end')}
      ${code(' = "F" "Estimada" "Estimado" ')}
      ${field('separate')}${text('Estimada')}${field('end')}
      ${text(' Ana:')}
    </w:p>
''');

      expect(markdown, 'Estimada Ana:');
    });

    test('un indice que abarca varios parrafos se lee entero', () async {
      final markdown = await markdownOf('''
    <w:p>${field('begin')}${code(' TOC ')}${field('separate')}${text('Introduccion 1')}</w:p>
    <w:p>${text('Metodo 2')}</w:p>
    <w:p>${text('Resultados 3')}${field('end')}</w:p>
    <w:p>${text('El cuerpo.')}</w:p>
''');

      expect(
        markdown,
        'Introduccion 1\n\nMetodo 2\n\nResultados 3\n\nEl cuerpo.',
      );
    });

    test('un campo simple sigue dando su resultado', () async {
      final markdown = await markdownOf('''
    <w:p>${text('Pagina ')}<w:fldSimple w:instr=" PAGE ">${text('7')}</w:fldSimple></w:p>
''');

      expect(markdown, 'Pagina 7');
    });

    test('un campo que nunca termina no se lleva el resto', () async {
      final markdown = await markdownOf('''
    <w:p>${text('Antes ')}${field('begin')}${code(' REF roto ')}${text('despues.')}</w:p>
    <w:p>${text('Otro parrafo.')}</w:p>
''');

      expect(markdown, 'Antes despues.\n\nOtro parrafo.');
    });
  });

  group('celdas combinadas (F22)', () {
    test('cada texto queda en su columna', () async {
      // Una celda que ocupa dos columnas y una fila que empieza con una
      // columna sin celda: sin completarlas, "C" quedaba bajo "b".
      const body = '''
    <w:tbl>
      <w:tr>
        <w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>c</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:trPr><w:gridBefore w:val="1"/></w:trPr>
        <w:tc><w:p><w:r><w:t>y</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>z</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
''';

      expect(
        await markdownOf(body),
        '| A |  | C |\n'
        '| --- | --- | --- |\n'
        '| a | b | c |\n'
        '|  | y | z |',
      );
    });
  });

  group('titulos y saltos (F22)', () {
    test(
      'el nivel de esquema 9 es texto independiente, no un titulo',
      () async {
        expect(
          await markdownOf(wordParagraph('Cuerpo', outlineLevel: 9)),
          'Cuerpo',
        );
      },
    );

    test('un salto de pagina al comienzo de un titulo no se escribe', () async {
      // Antes quedaba "#   \nCapitulo 2": un titulo vacio y un parrafo.
      const body = '''
    <w:p><w:r><w:t>Fin del uno.</w:t></w:r></w:p>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:br w:type="page"/></w:r>
      <w:r><w:t>Capitulo 2</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Fin del uno.\n\n# Capitulo 2');
    });

    test('un parrafo que es solo un salto de pagina no deja nada', () async {
      const body = '''
    <w:p><w:r><w:t>Antes.</w:t><w:br w:type="page"/></w:r></w:p>
    <w:p><w:r><w:br w:type="column"/></w:r></w:p>
    <w:p><w:r><w:t>Despues.</w:t></w:r></w:p>
''';

      expect(await markdownOf(body), 'Antes.\n\nDespues.');
    });

    test('en medio del texto es el salto de linea que Word muestra', () async {
      const body = '''
    <w:p><w:r><w:t>Arriba</w:t><w:br w:type="page"/><w:t>abajo</w:t></w:r></w:p>
''';

      expect(await markdownOf(body), 'Arriba  \nabajo');
    });

    test('un titulo de dos lineas lleva la almohadilla en cada una', () async {
      const body = '''
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:br/><w:t>Capitulo 1</w:t><w:br/><w:t>El comienzo</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), '# Capitulo 1\n# El comienzo');
    });

    test('el numero de una lista no va delante de un salto', () async {
      const body = '''
    <w:p>
      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:br/><w:t>Punto</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), '- Punto');
    });
  });

  group('listas definidas por un estilo de lista (F22)', () {
    test('se sigue el estilo hasta los niveles de verdad', () async {
      // La definicion que usa el parrafo esta vacia: solo dice "usar el
      // estilo MiLista". Sin seguirlo, la lista salia como vinetas "- ".
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  <w:styleLink w:val="MiLista"/>
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%1)"/></w:lvl>
</w:abstractNum>
<w:abstractNum w:abstractNumId="1"><w:numStyleLink w:val="MiLista"/></w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'''),
        'word/styles.xml': wordPart('w:styles', '''
<w:style w:type="numbering" w:styleId="MiLista">
  <w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>
</w:style>'''),
      };
      String item(String text) =>
          '''
<w:p>
  <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr></w:pPr>
  <w:r><w:t>$text</w:t></w:r>
</w:p>''';

      expect(
        await markdownOf(item('Uno') + item('Dos'), parts: parts),
        'a) Uno\n\nb) Dos',
      );
    });
  });

  group('las partes se buscan por sus relaciones (F22)', () {
    test('el cuerpo y la numeracion, donde el paquete diga', () async {
      final parts = {
        '_rels/.rels': _relationships([
          ('rId1', 'officeDocument', 'contenido/principal.xml'),
        ]),
        'contenido/principal.xml': wordPart('w:document', '''
<w:body>
  <w:p>
    <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="3"/></w:numPr></w:pPr>
    <w:r><w:t>El de verdad.</w:t></w:r>
  </w:p>
</w:body>'''),
        'contenido/_rels/principal.xml.rels': _relationships([
          ('rIdN', 'numbering', 'listas.xml'),
        ]),
        'contenido/listas.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="upperRoman"/><w:lvlText w:val="%1."/></w:lvl>
</w:abstractNum>
<w:num w:numId="3"><w:abstractNumId w:val="0"/></w:num>'''),
      };

      expect(
        await markdownOf(wordParagraph('No es este.'), parts: parts),
        'I. El de verdad.',
      );
    });
  });

  group('SmartArt y graficos (F22)', () {
    test('el texto de un SmartArt va como bloque, en su orden', () async {
      // Los elementos se leen del raiz a sus hijos, en el orden que Word
      // les da (`srcOrd`), no en el orden del archivo.
      final parts = {
        'word/_rels/document.xml.rels': _relationships([
          ('rIdDm', 'diagramData', 'diagrams/data1.xml'),
        ]),
        'word/diagrams/data1.xml': wordPart('dgm:dataModel', '''
<dgm:ptLst>
  <dgm:pt modelId="0" type="doc"><dgm:t><a:p/></dgm:t></dgm:pt>
  <dgm:pt modelId="3"><dgm:t><a:p><a:r><a:t>Detalle b</a:t></a:r></a:p></dgm:t></dgm:pt>
  <dgm:pt modelId="1"><dgm:t><a:p><a:r><a:t>La </a:t></a:r><a:r><a:t>idea</a:t></a:r></a:p></dgm:t></dgm:pt>
  <dgm:pt modelId="2"><dgm:t><a:p><a:r><a:t>Detalle a</a:t></a:r></a:p></dgm:t></dgm:pt>
</dgm:ptLst>
<dgm:cxnLst>
  <dgm:cxn modelId="10" srcId="0" destId="1" srcOrd="0"/>
  <dgm:cxn modelId="11" srcId="1" destId="3" srcOrd="1"/>
  <dgm:cxn modelId="12" srcId="1" destId="2" srcOrd="0"/>
</dgm:cxnLst>'''),
      };

      final markdown = await markdownOf('''
    <w:p>
      <w:r><w:t>Antes.</w:t></w:r>
      <w:r><w:drawing><wp:inline><a:graphic><a:graphicData>
        <dgm:relIds r:dm="rIdDm" r:lo="rIdLo" r:qs="rIdQs" r:cs="rIdCs"/>
      </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
    </w:p>
${wordParagraph('Despues.')}
''', parts: parts);

      expect(
        markdown,
        'Antes.\n\nLa idea  \nDetalle a  \nDetalle b\n\nDespues.',
      );
    });

    test('el titulo de un grafico y los de sus ejes se guardan', () async {
      final parts = {
        'word/_rels/document.xml.rels': _relationships([
          ('rIdCh', 'chart', 'charts/chart1.xml'),
        ]),
        'word/charts/chart1.xml': wordPart('c:chartSpace', '''
<c:chart>
  <c:title><c:tx><c:rich><a:p><a:r><a:t>Ventas 2024</a:t></a:r></a:p></c:rich></c:tx></c:title>
  <c:plotArea><c:valAx><c:title><c:tx><c:rich><a:p><a:r><a:t>Pesos</a:t></a:r></a:p></c:rich></c:tx></c:title>
  <c:txPr><a:p><a:pPr/><a:endParaRPr/></a:p></c:txPr></c:valAx></c:plotArea>
</c:chart>'''),
      };

      final markdown = await markdownOf('''
    <w:p><w:r><w:drawing><wp:inline><a:graphic><a:graphicData>
      <c:chart r:id="rIdCh"/>
    </a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
''', parts: parts);

      expect(markdown, 'Ventas 2024  \nPesos');
    });
  });

  group('control de cambios (F22)', () {
    test('un parrafo borrado no avanza la numeracion', () async {
      final parts = {
        'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'''),
      };
      const numPr =
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>';

      final markdown = await markdownOf('''
    <w:p><w:pPr>$numPr</w:pPr><w:r><w:t>Uno</w:t></w:r></w:p>
    <w:p>
      <w:pPr>$numPr<w:rPr><w:del w:id="1" w:author="Ana"/></w:rPr></w:pPr>
      <w:del w:id="2" w:author="Ana"><w:r><w:delText>Borrado</w:delText></w:r></w:del>
    </w:p>
    <w:p><w:pPr>$numPr</w:pPr><w:r><w:t>Dos</w:t></w:r></w:p>
''', parts: parts);

      expect(markdown, '1. Uno\n\n2. Dos');
    });

    test('una fila borrada no se guarda', () async {
      const body = '''
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>Queda</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr>
        <w:trPr><w:del w:id="1" w:author="Ana"/></w:trPr>
        <w:tc><w:p><w:del w:id="2" w:author="Ana"><w:r><w:delText>Se fue</w:delText></w:r></w:del></w:p></w:tc>
      </w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>Tambien</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
''';

      expect(await markdownOf(body), '| Queda |\n| --- |\n| Tambien |');
    });
  });

  group('texto oculto, ruby y fragmentos incrustados (F22)', () {
    test('el texto oculto se guarda: es texto del documento', () async {
      // Decision documentada en el lector: Word lo muestra al activar
      // "mostrar todo", y perderlo seria perder texto.
      const body = '''
    <w:p>
      <w:r><w:t xml:space="preserve">Respuesta: </w:t></w:r>
      <w:r><w:rPr><w:vanish/></w:rPr><w:t>42</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'Respuesta: 42');
    });

    test('la lectura de un ruby va despues, entre parentesis', () async {
      const body = '''
    <w:p>
      <w:r><w:ruby>
        <w:rubyPr><w:rubyAlign w:val="center"/></w:rubyPr>
        <w:rt><w:r><w:t>かんじ</w:t></w:r></w:rt>
        <w:rubyBase><w:r><w:t>漢字</w:t></w:r></w:rubyBase>
      </w:ruby></w:r>
      <w:r><w:t>です</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), '漢字(かんじ)です');
    });

    test('un fragmento HTML o de texto se lee en su lugar', () async {
      final parts = {
        'word/_rels/document.xml.rels': _relationships([
          ('rIdH', 'aFChunk', 'fragmento.htm'),
          ('rIdT', 'aFChunk', 'notas.txt'),
        ]),
        'word/fragmento.htm':
            '<html><head><title>No</title></head>'
            '<body><p>Hola <b>mundo</b>.</p></body></html>',
        'word/notas.txt': 'Linea uno\nLinea dos',
      };

      final markdown = await markdownOf('''
${wordParagraph('Antes.')}
    <w:altChunk r:id="rIdH"/>
    <w:altChunk r:id="rIdT"/>
${wordParagraph('Despues.')}
''', parts: parts);

      expect(
        markdown,
        'Antes.\n\nHola **mundo**.\n\nLinea uno\nLinea dos\n\nDespues.',
      );
    });

    test('un fragmento en otro formato no frena y queda registrado', () async {
      final logger = _RecordingLogger();
      final parts = {
        'word/_rels/document.xml.rels': _relationships([
          ('rIdR', 'aFChunk', 'fragmento.rtf'),
        ]),
        'word/fragmento.rtf': r'{\rtf1 Hola}',
      };

      final result = await DocxParser(logger: logger).parseBytes(
        buildDocx(
          body: '${wordParagraph('Texto.')}<w:altChunk r:id="rIdR"/>',
          parts: parts,
        ),
      );

      expect(result.markdown, 'Texto.');
      expect(logger.warnings.single, contains('word/fragmento.rtf'));
    });
  });

  group('lo que antes rompia el documento (F22)', () {
    test('un simbolo con un codigo invalido queda como reemplazo', () async {
      const body = '''
    <w:p>
      <w:r><w:t>a</w:t></w:r>
      <w:r><w:sym w:font="Symbol" w:char="FFFFFFFF"/></w:r>
      <w:r><w:t>b</w:t></w:r>
    </w:p>
''';

      expect(await markdownOf(body), 'a�b');
    });

    test('una parte opcional danada se saltea y queda registrada', () async {
      final logger = _RecordingLogger();
      final docx = buildDocx(
        body: wordParagraph('Punto', listLevel: 0) + wordParagraph('Sigue.'),
        parts: {
          'word/numbering.xml': wordPart('w:numbering', '''
<w:abstractNum w:abstractNumId="0">
  <w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'''),
        },
      );

      final result = await DocxParser(
        logger: logger,
      ).parseBytes(_withDamagedPart(docx, 'word/numbering.xml'));

      // Sin la numeracion, el punto queda como vineta: el texto, entero.
      expect(result.markdown, '- Punto\n\nSigue.');
      expect(
        logger.warnings.single,
        allOf(contains('word/numbering.xml'), contains('dañada')),
      );
    });
  });

  group('rendimiento y marcas (F22)', () {
    test('miles de pedazos con el mismo formato se juntan enteros', () async {
      final runs = List.filled(
        20000,
        '<w:r><w:rPr><w:b/></w:rPr><w:t>a</w:t></w:r>',
      ).join();

      expect(await markdownOf('<w:p>$runs</w:p>'), '**${'a' * 20000}**');
    });

    test('la negrita y la cursiva superpuestas se anidan', () async {
      // Antes: `**super*****cali*****fragil**`, que se lee de mas de una
      // forma.
      const body = '''
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>super</w:t></w:r>
      <w:r><w:rPr><w:b/><w:i/></w:rPr><w:t>cali</w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t>fragil</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:rPr><w:i/></w:rPr><w:t xml:space="preserve">una </w:t></w:r>
      <w:r><w:rPr><w:b/><w:i/></w:rPr><w:t xml:space="preserve">frase </w:t></w:r>
      <w:r><w:rPr><w:i/></w:rPr><w:t>entera</w:t></w:r>
    </w:p>
''';

      expect(
        await markdownOf(body),
        '**super*cali*fragil**\n\n*una **frase** entera*',
      );
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
