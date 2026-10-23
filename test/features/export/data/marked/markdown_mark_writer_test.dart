import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/features/export/data/marked/markdown_mark_writer.dart';
import 'package:sinapsis/features/export/domain/entities/document_mark.dart';
import 'package:sinapsis/features/transform/data/documents/plain_text_parser.dart';
import 'package:sinapsis/features/transform/domain/documents/document_parser.dart';

const _yellow = 0xFFFFF59D;
const _violet = 0xFFB39DDB;

DocumentMark _mark(
  String text,
  String excerpt, {
  int occurrence = 0,
  int color = _yellow,
  HighlightStyle style = HighlightStyle.fill,
}) {
  var start = -1;
  for (var i = 0; i <= occurrence; i++) {
    start = text.indexOf(excerpt, start + 1);
    expect(start, isNonNegative, reason: '«$excerpt» no está en el texto');
  }
  return DocumentMark(
    start: start,
    end: start + excerpt.length,
    excerpt: excerpt,
    color: color,
    style: style,
  );
}

void main() {
  const writer = MarkdownMarkWriter();

  String mark(String md, List<DocumentMark> marks, {String? extracted}) =>
      writer.write(markdown: md, text: extracted ?? md, marks: marks);

  group('MarkdownMarkWriter', () {
    test('un tramo de fondo va entre ==', () {
      const md = 'Hola mundo cruel.\n';
      expect(mark(md, [_mark(md, 'mundo')]), 'Hola ==mundo== cruel.\n');
    });

    test('un subrayado va entre <u>', () {
      const md = 'Hola mundo cruel.\n';
      expect(
        mark(md, [_mark(md, 'mundo cruel', style: HighlightStyle.underline)]),
        'Hola <u>mundo cruel</u>.\n',
      );
    });

    test('lo que no es marcado queda igual, hasta los saltos de línea de '
        'Windows y los espacios del final', () {
      const md = 'Uno dos  \r\nTres cuatro\r\n\r\nCinco\r\n';
      final result = mark(md, [_mark(md, 'dos')]);
      expect(result, 'Uno ==dos==  \r\nTres cuatro\r\n\r\nCinco\r\n');
    });

    test('un tramo que cruza renglones y párrafos se parte uno por '
        'renglón, sin los espacios de los bordes', () {
      const md =
          'Primer párrafo que sigue\ncon otro renglón.\n\nSegundo '
          'párrafo.\n';
      final result = mark(md, [
        _mark(md, 'que sigue\ncon otro renglón.\n\nSegundo párrafo'),
      ]);
      expect(
        result,
        'Primer párrafo ==que sigue==\n==con otro renglón.==\n\n'
        '==Segundo párrafo==.\n',
      );
    });

    test(
      'no marca el comienzo de un bloque: encabezado, lista, cita, tarea',
      () {
        const md =
            '## Los pasos\n'
            '1. Primero esto\n'
            '- Segundo aquello\n'
            '- [ ] Tercero pendiente\n'
            '> Cita larga\n';
        final result = mark(md, [
          _mark(md, 'Los pasos\n1. Primero esto'),
          _mark(md, 'Segundo aquello'),
          _mark(md, 'Tercero pendiente\n> Cita larga'),
        ]);
        expect(
          result,
          '## ==Los pasos==\n'
          '1. ==Primero esto==\n'
          '- ==Segundo aquello==\n'
          '- [ ] ==Tercero pendiente==\n'
          '> ==Cita larga==\n',
        );
      },
    );

    test('un tramo que empieza en el # o en el número de una lista no lo '
        'envuelve', () {
      const md = '### Título aquí\n\n12. Ítem doce\n';
      final result = mark(md, [
        // Desde el mismo `#`, y desde el `12.`.
        _mark(md, '### Título aquí'),
        _mark(md, '12. Ítem doce'),
      ]);
      expect(result, '### ==Título aquí==\n\n12. ==Ítem doce==\n');
    });

    test('un tramo que cubre una negrita entera la deja adentro', () {
      const md = 'Ella dijo **esto** y aquello más.\n';
      expect(
        mark(md, [_mark(md, 'dijo **esto** y aquello')]),
        'Ella ==dijo **esto** y aquello== más.\n',
      );
    });

    test('un tramo que corta una negrita por la mitad se parte alrededor '
        'de las marcas', () {
      const md = 'Una **frase en negrita y** un resto normal.\n';
      final result = mark(md, [_mark(md, 'negrita y** un resto')]);
      expect(result, 'Una **frase en ==negrita y==** ==un resto== normal.\n');
    });

    test('un tramo que empieza adentro de una negrita y termina afuera', () {
      const md = 'Una **frase fuerte** y su resto.\n';
      final result = mark(md, [_mark(md, 'fuerte** y su')]);
      expect(result, 'Una **frase ==fuerte==** ==y su== resto.\n');
    });

    test('un enlace completo queda adentro; un enlace cortado no marca su '
        'dirección', () {
      const md = 'Mirá [este texto](http://ejemplo.com/a_b) para ver más.\n';
      expect(
        mark(md, [_mark(md, 'Mirá [este texto](http://ejemplo.com/a_b) para')]),
        '==Mirá [este texto](http://ejemplo.com/a_b) para== ver más.\n',
      );
      expect(
        mark(md, [_mark(md, 'texto](http://ejemplo.com/a_b) para')]),
        'Mirá [este ==texto==](http://ejemplo.com/a_b) ==para== ver más.\n',
      );
    });

    test('un tramo que empieza adentro de un código no se marca', () {
      const md = 'Usá `una_variable larga` luego.\n';
      expect(mark(md, [_mark(md, 'variable larga')]), md);
      // Si el código queda entero adentro, sí.
      expect(
        mark(md, [_mark(md, 'Usá `una_variable larga` luego')]),
        '==Usá `una_variable larga` luego==.\n',
      );
    });

    test('un bloque de código y el encabezado YAML no se marcan', () {
      const md =
          '---\n'
          'title: Prueba de Texto normal\n'
          '---\n'
          'Texto normal aquí.\n'
          '```dart\n'
          'var Texto normal = 1;\n'
          '```\n'
          'Texto normal final.\n';
      final result = mark(md, [
        _mark(md, 'Texto normal'),
        _mark(md, 'Texto normal', occurrence: 1),
        _mark(md, 'Texto normal', occurrence: 2),
        _mark(md, 'Texto normal', occurrence: 3),
      ]);
      // El del encabezado y el del bloque de código quedan como estaban.
      expect(
        result,
        '---\n'
        'title: Prueba de Texto normal\n'
        '---\n'
        '==Texto normal== aquí.\n'
        '```dart\n'
        'var Texto normal = 1;\n'
        '```\n'
        '==Texto normal== final.\n',
      );
    });

    test('un --- del principio que nunca se cierra es una línea, no un '
        'encabezado', () {
      const md = '---\nTexto de después.\n';
      expect(mark(md, [_mark(md, 'Texto')]), '---\n==Texto== de después.\n');
    });

    test('en una fila de tabla, un tramo no cruza de celda en celda', () {
      const md =
          '| Año | Hecho |\n| --- | --- |\n| 1789 | Toma de la Bastilla |\n';
      final result = mark(md, [_mark(md, '1789 | Toma de la')]);
      expect(
        result,
        '| Año | Hecho |\n| --- | --- |\n'
        '| ==1789== | ==Toma de la== Bastilla |\n',
      );
    });

    test('un tramo que no se encuentra se saltea', () {
      const md = 'Hola mundo.\n';
      expect(
        mark(md, [
          const DocumentMark(
            start: 0,
            end: 3,
            excerpt: 'no está',
            color: _yellow,
          ),
        ]),
        md,
      );
    });

    test('varios tramos; si se pisan gana el último; el estilo sigue a cada '
        'uno', () {
      const md = 'Uno dos tres cuatro cinco.\n';
      final result = mark(md, [
        _mark(md, 'dos tres cuatro'),
        _mark(md, 'tres', color: _violet, style: HighlightStyle.underline),
      ]);
      expect(result, 'Uno ==dos== <u>tres</u> ==cuatro== cinco.\n');
    });

    test('se ubica por las letras cuando el texto extraído no es igual al '
        'Markdown: otra puntuación, o de más al principio', () {
      const md =
          'La **casa** de la *vecina* es azul.\n'
          'La casa de la vecina es roja.\n';
      // El texto extraído trae un título antes y no tiene los asteriscos.
      const extracted =
          'Notas\n\nLa casa de la vecina es azul.\n'
          'La casa de la vecina es roja.';
      final second = DocumentMark(
        start: extracted.lastIndexOf('La casa de la vecina'),
        end:
            extracted.lastIndexOf('La casa de la vecina') +
            'La casa de la vecina'.length,
        excerpt: 'La casa de la vecina',
        color: _yellow,
      );
      final result = mark(md, [second], extracted: extracted);
      expect(
        result,
        'La **casa** de la *vecina* es azul.\n'
        '==La casa de la vecina== es roja.\n',
      );
    });

    test(
      'sobre un .md real con marca de orden de bytes: se lee y se marca',
      () async {
        final bytes = utf8.encode(
          '\u{FEFF}# Apuntes\n\nLa **mitocondria** es la central energética.\n',
        );
        final markdown = decodePlainText(bytes);
        final parsed = await const PlainTextParser().parse(
          DocumentSource.memory(bytes),
        );
        final result = mark(markdown, [
          _mark(parsed.markdown, 'central energética'),
        ], extracted: parsed.markdown);
        expect(
          result,
          '# Apuntes\n\nLa **mitocondria** es la ==central energética==.\n',
        );
      },
    );

    test('un tramo sin letras ni números no se marca', () {
      const md = 'Antes *** despues.\n';
      expect(
        mark(md, [
          const DocumentMark(start: 7, end: 10, excerpt: '***', color: _yellow),
        ]),
        md,
      );
    });

    test('dos tramos pegados: lo que cierra va antes de lo que abre', () {
      const md = 'Una palabra: foobar.\n';
      expect(
        mark(md, [
          _mark(md, 'foo'),
          _mark(md, 'bar', style: HighlightStyle.underline),
        ]),
        'Una palabra: ==foo==<u>bar</u>.\n',
      );
    });

    test('un tramo que termina adentro de una etiqueta HTML no la rompe', () {
      const md = 'Ver <span class="x">texto</span> ahora.\n';
      expect(
        mark(md, [_mark(md, 'Ver <span class')]),
        '==Ver== <span class="x">texto</span> ahora.\n',
      );
    });

    test('un tramo que cierra un enlace y abre otro se parte en los textos '
        'de los enlaces', () {
      const md =
          'Un [enlace uno](http://a.com) y [otro enlace](http://b.com) fin.\n';
      expect(
        mark(md, [_mark(md, 'uno](http://a.com) y [otro')]),
        'Un [enlace ==uno==](http://a.com) ==y== '
        '[==otro== enlace](http://b.com) fin.\n',
      );
    });

    test('un tramo que abre una negrita y no la cierra se parte', () {
      const md = 'Una **frase fuerte** y su resto.\n';
      expect(
        mark(md, [_mark(md, 'Una **frase')]),
        '==Una== **==frase== fuerte** y su resto.\n',
      );
    });

    test('sin tramos devuelve el mismo Markdown', () {
      const md = 'Hola.\n';
      expect(mark(md, []), md);
    });
  });
}
