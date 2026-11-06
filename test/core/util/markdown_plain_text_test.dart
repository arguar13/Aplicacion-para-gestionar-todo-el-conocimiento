import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/markdown_inline.dart';
import 'package:sinapsis/core/util/markdown_plain_text.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

import '../../support/wikipedia_fixtures.dart';

/// Lo que se lee de un texto en Markdown, para el chat y para el modelo (F46,
/// paso 5e).
const _wiki = 'https://es.wikipedia.org/wiki';

void main() {
  group('lo en línea', () {
    test('un enlace queda en su texto, sin la dirección', () {
      expect(
        markdownPlainText(
          'En 1905, [Frederick Frost Blackman]($_wiki/Frederick_Frost_Blackman) '
          'midió',
        ),
        'En 1905, Frederick Frost Blackman midió',
      );
    });

    test('una dirección con paréntesis adentro no deja nada colgando', () {
      expect(
        markdownPlainText('el [método]($_wiki/Hip%C3%B3tesis_(m%C3%A9todo)).'),
        'el método.',
      );
    });

    test('una imagen queda en su texto alternativo', () {
      expect(
        markdownPlainText('Mirá ![una hoja verde](https://x.org/a.jpg) acá'),
        'Mirá una hoja verde acá',
      );
    });

    test('una imagen sin texto alternativo, entre dos palabras, no deja un '
        'espacio doble', () {
      expect(
        markdownPlainText(
          'antes ![](https://upload.wikimedia.org/a.jpg) '
          'después',
        ),
        'antes después',
      );
      // Una foto enlazada a su ficha, como las de Wikipedia.
      expect(
        markdownPlainText(
          'antes [![](//upload.wikimedia.org/a.jpg)]($_wiki/Archivo:a.jpg) '
          'después',
        ),
        'antes después',
      );
    });

    test('`[[Título]]` queda en el título', () {
      expect(markdownPlainText('ver [[La loba]] y'), 'ver La loba y');
    });

    test('el código y el énfasis quedan en su texto', () {
      expect(
        markdownPlainText(
          'un **dato**, una *idea*, otra _más_ y `x = 1` o `` `y` ``',
        ),
        'un dato, una idea, otra más y x = 1 o `y`',
      );
    });

    test('el HTML en línea queda en su texto', () {
      expect(
        markdownPlainText(
          'el CO<sub>2</sub>, el m<sup>2</sup>, '
          '<a href="https://x.org">un sitio</a> y '
          '<img src="a.png" alt="un mapa"> o <img src="b.png">.',
        ),
        'el CO2, el m2, un sitio y un mapa o .',
      );
      // El texto alternativo escapado no se lee: lo que se ve tiene que ser un
      // pedazo del crudo, y «a &amp; b» no lo es.
      expect(markdownPlainText('x <img src="b.png" alt="a &amp; b"> y'), 'x y');
    });

    test('qué es cada construcción y qué tramo se lee de ella '
        '(`markdownInlineText`)', () {
      MarkdownInlineText read(String text) =>
          markdownInlineText(markdownInlinePattern.firstMatch(text)!);

      expect(read('CO<sub>2</sub>'), (
        kind: MarkdownInline.subscript,
        start: 7,
        end: 8,
      ));
      expect(read('m<sup>2</sup>').kind, MarkdownInline.superscript);
      expect(read('`x`').kind, MarkdownInline.code);
      expect(read('[[La loba]]').kind, MarkdownInline.wikiLink);
      expect(read('[a](b)').kind, MarkdownInline.link);
      expect(read('**a**').kind, MarkdownInline.bold);
      expect(read('_a_').kind, MarkdownInline.italic);
      // Una imagen sin texto alternativo —o con uno de espacios— no deja
      // nada: ni siquiera el espacio.
      expect(read('![ ](https://x.org/a.jpg)'), (
        kind: MarkdownInline.image,
        start: 25,
        end: 25,
      ));
      expect(read('![un mapa](a.jpg)'), (
        kind: MarkdownInline.image,
        start: 2,
        end: 9,
      ));
    });

    test('combinadas, cada una adentro de la otra', () {
      expect(
        markdownPlainText(
          '**[la luz *solar*]($_wiki/Luz_solar)** y '
          '[**negrita** en un enlace]($_wiki/X)',
        ),
        'la luz solar y negrita en un enlace',
      );
    });

    test('lo que no es Markdown queda tal cual', () {
      expect(markdownPlainText('2 * 3 * 4 = 24'), '2 * 3 * 4 = 24');
      expect(markdownPlainText('var_uno_dos'), 'var_uno_dos');
      expect(markdownPlainText('[corchetes] sueltos'), '[corchetes] sueltos');
    });
  });

  group('las notas al pie', () {
    test('la llamada de Wikipedia —un enlace a la nota— se va', () {
      expect(
        markdownPlainText(
          'la fotosíntesis<sup>[[1]](#cite_note-1)</sup> es '
          'antigua.[[12]](#cite_note-12)',
        ),
        'la fotosíntesis es antigua.',
      );
    });

    test('y la suelta, con número, letra o «nota»', () {
      expect(
        markdownPlainText('uno[1] dos [n. 2] tres[a] cuatro [cita requerida].'),
        'uno dos tres cuatro .',
      );
    });

    test('adentro del código no es una nota', () {
      expect(markdownPlainText('el `x[1]` de la lista'), 'el x[1] de la lista');
    });

    test('unos corchetes con otra cosa adentro no son una nota', () {
      expect(markdownPlainText('el rango [1, 2]'), 'el rango [1, 2]');
      expect(markdownPlainText('el año [1905a]'), 'el año [1905a]');
    });
  });

  group('lo de bloque', () {
    test('un título, sin sus numerales', () {
      expect(markdownPlainText('### Siglo XX\n\nEn 1905'), 'Siglo XX\nEn 1905');
    });

    test('un título corta el párrafo de arriba aunque no haya un renglón en '
        'blanco entre los dos', () {
      expect(markdownPlainBlocks('Un párrafo\n## Título\nSu texto').toList(), [
        'Un párrafo',
        'Título',
        'Su texto',
      ]);
    });

    test('un párrafo en varios renglones es un bloque', () {
      expect(
        markdownPlainBlocks('La república\ncayó.\n\nOtro párrafo.').toList(),
        ['La república cayó.', 'Otro párrafo.'],
      );
    });

    test('las viñetas y los números de lista; el número queda', () {
      expect(
        markdownPlainBlocks(
          '- uno\n* dos\n+ tres\n  - anidado\n1. primero\n2) segundo',
        ).toList(),
        ['uno', 'dos', 'tres', 'anidado', '1. primero', '2) segundo'],
      );
    });

    test('una cita, sin sus `>`', () {
      expect(
        markdownPlainText('> Lo dijo **él**.\n> > Y otro.'),
        'Lo dijo él. Y otro.',
      );
    });

    test('un separador no se lee', () {
      expect(markdownPlainBlocks('Uno.\n---\nDos.\n* * *').toList(), [
        'Uno.',
        'Dos.',
      ]);
    });

    test('un bloque de código, tal cual y sin sus cercas', () {
      expect(
        markdownPlainBlocks(
          'Antes.\n```dart\nfinal x = [y](z);\n**no**\n```\nDespués.',
        ).toList(),
        ['Antes.', 'final x = [y](z);\n**no**', 'Después.'],
      );
      expect(markdownPlainBlocks('~~~\nsin cerrar').toList(), ['sin cerrar']);
      // Con los fines de renglón de Windows, el código no se queda con ellos.
      expect(markdownPlainBlocks('```\r\nx = 1\r\ny\r\n```\r\n').toList(), [
        'x = 1\ny',
      ]);
    });

    test('las filas de una tabla, con sus celdas separadas por una coma', () {
      expect(
        markdownPlainBlocks(
          '| Pigmento | Color |\n|---|:---:|\n| [Clorofila]($_wiki/C) | '
          'verde |',
        ).toList(),
        ['Pigmento, Color', 'Clorofila, verde'],
      );
    });

    test('un renglón que no tiene nada que leer no es un bloque', () {
      expect(
        markdownPlainBlocks(
          'Uno.\n\n![](https://x.org/a.jpg)\n\nDos.',
        ).toList(),
        ['Uno.', 'Dos.'],
      );
    });

    test('solo el tramo pedido, y con los fines de renglón de Windows', () {
      const text = 'Antes.\r\n## Título\r\nTexto.\r\nDespués.';
      expect(
        markdownPlainBlocks(
          text,
          start: text.indexOf('##'),
          end: text.indexOf('Después'),
        ).toList(),
        ['Título', 'Texto.'],
      );
    });
  });

  group('el pasaje que viaja al chat', () {
    test('cada bloque es una oración: un título sin punto recibe uno', () {
      expect(
        readablePassage(
          '## Siglo XX\n\nEn 1905, midió.\n\n- una idea\n- otra!',
          markdown: true,
          maxChars: 2000,
        ),
        'Siglo XX. En 1905, midió. una idea. otra!',
      );
      expect(
        readablePassage(
          '## ¿Qué es?\n\n«Así.»',
          markdown: true,
          maxChars: 2000,
        ),
        '¿Qué es? «Así.»',
      );
    });

    test('sin Markdown, tal cual y en un renglón: un punto partiría una '
        'oración', () {
      expect(
        readablePassage(
          'la síntesis de\nglucosa [1] **x**',
          markdown: false,
          maxChars: 2000,
        ),
        'la síntesis de glucosa [1] **x**',
      );
    });

    test('el tope cuenta letras legibles, no direcciones', () {
      final link = '[palabra]($_wiki/${'x' * 200})';
      final text = List.filled(400, link).join(' ');
      final passage = readablePassage(text, markdown: true, maxChars: 2000);
      expect(passage, isNot(contains('http')));
      expect(passage.length, greaterThan(1600));
      expect(passage.length, lessThanOrEqualTo(2001));
      expect(passage, endsWith('palabra…'));
    });

    test('lo largo se corta en una palabra entera; una palabra sola más '
        'larga que el tope, en el tope', () {
      final long = List.filled(600, 'palabra').join(' ');
      expect(
        readablePassage(long, markdown: false, maxChars: 100),
        '${List.filled(12, 'palabra').join(' ')}…',
      );
      expect(
        readablePassage('a' * 150, markdown: false, maxChars: 100),
        '${'a' * 100}…',
      );
      // Si el último espacio queda lejos del tope, no se tira casi todo para
      // terminar en una palabra entera.
      expect(
        readablePassage('aa ${'b' * 150}', markdown: false, maxChars: 100),
        'aa ${'b' * 97}…',
      );
    });

    test('justo en el tope, entero y sin «…»', () {
      expect(
        readablePassage('a' * 100, markdown: false, maxChars: 100),
        'a' * 100,
      );
    });

    test('fuera del texto, o sin nada que leer, vacío', () {
      expect(readablePassage('abc', start: 9, markdown: true, maxChars: 9), '');
      expect(
        readablePassage('abc', start: -1, markdown: true, maxChars: 9),
        '',
      );
      expect(
        readablePassage(
          '![](https://x.org/a.jpg)',
          markdown: true,
          maxChars: 9,
        ),
        '',
      );
    });
  });

  group('lo en línea es lo que muestra el lector', () {
    // Una sola regla: lo que viaja al chat de cada renglón es lo que el
    // lector (`RenderedMarkdown`) muestra de él, menos las llamadas a notas
    // al pie. Si alguna vez difirieran, esta prueba lo dice.
    String shown(String line) => RenderedMarkdown.parse(line).displayText
        .replaceFirst(RegExp('^• '), '')
        .replaceAll(markdownFootnoteCall, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    void sameAsReader(String markdown) {
      var lines = 0;
      for (final line in markdown.split('\n')) {
        // Un separador el lector lo muestra como una raya; acá no se lee.
        if (RegExp(r'^\s*(?:-{3,}|\*{3,})\s*$').hasMatch(line)) continue;
        expect(markdownPlainText(line), shown(line), reason: line);
        lines++;
      }
      expect(lines, greaterThan(0));
    }

    test('en el recorte de Fotosíntesis', () {
      final markdown = wikipediaFotosintesis();
      sameAsReader(markdown);
      final plain = markdownPlainText(markdown);
      expect(plain, isNot(contains('](')));
      expect(plain, isNot(contains('http')));
      expect(plain, isNot(contains('<sub>')));
    });

    test('en el de Edad Media', () {
      sameAsReader(wikipediaMarkdown('edad_media', 'Edad_Media'));
    });

    test('en el párrafo real de Fotosíntesis, con sus notas al pie', () {
      final paragraph = File(
        'test/fixtures/web/wikipedia_fotosintesis_parrafo.md',
      ).readAsStringSync();
      sameAsReader(paragraph);
      final plain = markdownPlainText(paragraph);
      expect(plain, isNot(contains('[1]')));
      expect(plain, isNot(contains('cite_note')));
      expect(plain, startsWith('La fotosíntesis o función clorofílica es'));
    });

    test('en cada construcción, sola y combinada', () {
      sameAsReader(
        [
          '## Un **título** con [enlace]($_wiki/X)',
          '- una viñeta con *cursiva* y `código`',
          '> una cita con ![una foto](https://x.org/a.jpg)',
          'un [[Título]] y <a href="https://x.org">otro</a> y CO<sub>2</sub>',
          'una foto sin nada ![](https://x.org/a.jpg) entre dos palabras',
          '<img src="a.png" alt="un mapa"> y <img src="b.png" alt="a &amp; b">',
          'el `` `y` `` y 2 * 3 * 4 y var_uno_dos',
          '**[la luz *solar*]($_wiki/Luz_solar)**<sup>[[1]](#cite_note-1)</sup>',
        ].join('\n'),
      );
    });
  });
}
