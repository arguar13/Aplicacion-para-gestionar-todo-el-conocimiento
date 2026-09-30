import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';

/// El conversor que comparten el lector de EPUB y el de páginas web (F22).
///
/// Cada prueba compara el resultado entero, carácter por carácter: lo que se
/// verifica es que el texto del original llegue igual, y un `contains` no ve
/// una barra invertida agregada ni un espacio perdido.
void main() {
  group('el texto no se escapa', () {
    test('ni corchetes, ni números con punto, ni guiones bajos, ni '
        'asteriscos', () {
      // html2md escribía "\[1\]", "1\. Intro", "a\_b\_c" y "2\*3\*4":
      // barras que el original no tiene.
      expect(
        htmlToMarkdown(
          '<p>Ver [1] y la nota.</p><p>1. Intro</p><p>a_b_c y 2*3*4</p>',
        ),
        'Ver [1] y la nota.\n\n1. Intro\n\na_b_c y 2*3*4',
      );
    });

    test('las entidades llegan traducidas, una sola vez', () {
      expect(
        htmlToMarkdown('<p>&amp;lt; &#233; &eacute; &quot;x&quot;</p>'),
        '&lt; é é "x"',
      );
    });
  });

  group('superíndices y subíndices', () {
    test('quedan marcados, no pegados al número', () {
      // html2md dejaba "10<sup>6</sup>" como "106": otro número.
      expect(
        htmlToMarkdown('<p>10<sup>6</sup> moléculas de H<sub>2</sub>O</p>'),
        '10<sup>6</sup> moléculas de H<sub>2</sub>O',
      );
    });
  });

  group('lo que no es texto del documento', () {
    test('el head —título, CSS, JavaScript— no se vuelca', () {
      expect(
        htmlToMarkdown(
          [
            '<html><head><title>Título interno</title>',
            '<style>p { color: red }</style><script>var x = 1;</script>',
            '</head><body><p>Hola</p></body></html>',
          ].join(),
        ),
        'Hola',
      );
    });

    test('ni los scripts, estilos y plantillas que haya en el cuerpo', () {
      expect(
        htmlToMarkdown(
          [
            '<p>Antes</p><script>alert(1)</script><style>b{}</style>',
            '<noscript>Activá JavaScript</noscript>',
            '<template><p>molde</p></template><p>Después</p>',
          ].join(),
        ),
        'Antes\n\nDespués',
      );
    });
  });

  group('los espacios', () {
    test('los de formato del HTML se colapsan; el espacio duro no', () {
      // En HTML, los espacios y saltos repetidos del código fuente se ven
      // como uno solo: no son contenido. `&nbsp;` sí lo es.
      expect(
        htmlToMarkdown('<p>  uno\n     dos&nbsp;&nbsp;tres  </p>'),
        'uno dos  tres',
      );
    });

    test('dentro de <pre> no se toca ni un espacio', () {
      expect(
        htmlToMarkdown('<pre>  a   b\n\tc  \n</pre>'),
        '```\n  a   b\n\tc  \n```',
      );
    });

    test('un <pre> con comillas invertidas lleva una cerca más larga', () {
      expect(
        htmlToMarkdown('<pre>```\ncódigo\n```</pre>'),
        '````\n```\ncódigo\n```\n````',
      );
    });

    test('<br> es un salto de línea simple, sin barras ni espacios', () {
      expect(
        htmlToMarkdown('<p>verso uno<br>verso dos<br/>\n  verso tres</p>'),
        'verso uno\nverso dos\nverso tres',
      );
    });
  });

  group('la estructura', () {
    test('títulos con almohadillas según su nivel', () {
      expect(
        htmlToMarkdown('<h1>Uno</h1><h2>Dos</h2><h6>Seis</h6>'),
        '# Uno\n\n## Dos\n\n###### Seis',
      );
    });

    test('un título en dos líneas conserva las dos, las dos como título', () {
      expect(
        htmlToMarkdown('<h2>Capítulo 1<br>El comienzo</h2>'),
        '## Capítulo 1\n## El comienzo',
      );
    });

    test('negrita, cursiva, código, enlaces e imágenes', () {
      expect(
        htmlToMarkdown(
          '<p>Un <strong>fuerte</strong>, <em>suave </em>y <code>x = 1</code> '
          'con <a href="https://x.org/a" title="globo">enlace</a> e '
          '<img src="f.png" alt="una foto"></p>',
        ),
        'Un **fuerte**, *suave* y `x = 1` con [enlace](https://x.org/a) e '
        '![una foto](f.png)',
      );
    });

    test('una dirección con espacios va entera entre <>', () {
      expect(
        htmlToMarkdown('<p><a href="notas/la nota.html">ver</a></p>'),
        '[ver](<notas/la nota.html>)',
      );
    });

    test('un ancla sin dirección es solo su texto', () {
      // Los libros marcan así cada página del impreso.
      expect(
        htmlToMarkdown('<p><a id="p12"></a>Texto de la página</p>'),
        'Texto de la página',
      );
    });

    test('un enlace que envuelve párrafos no los junta', () {
      expect(
        htmlToMarkdown('<a href="x"><p>uno</p><p>dos</p></a>'),
        'uno\n\ndos',
      );
    });

    test('listas con viñetas, anidadas', () {
      expect(
        htmlToMarkdown(
          '<ul><li>uno<ul><li>sub</li></ul></li><li>dos</li></ul>',
        ),
        '- uno\n  - sub\n- dos',
      );
    });

    test('listas numeradas con el número real: start y value', () {
      expect(
        htmlToMarkdown(
          '<ol start="3"><li>c</li><li value="7">g</li><li>h</li></ol>',
        ),
        '3. c\n7. g\n8. h',
      );
    });

    test('listas con letras o romanos conservan sus letras', () {
      expect(
        htmlToMarkdown('<ol type="a"><li>x</li><li>y</li></ol>'),
        'a. x\nb. y',
      );
      expect(
        htmlToMarkdown('<ol type="I" start="3"><li>x</li><li>y</li></ol>'),
        'III. x\nIV. y',
      );
    });

    test('una lista invertida cuenta hacia atrás', () {
      expect(
        htmlToMarkdown('<ol reversed><li>x</li><li>y</li><li>z</li></ol>'),
        '3. x\n2. y\n1. z',
      );
    });

    test('citas', () {
      expect(
        htmlToMarkdown('<blockquote><p>uno</p><p>dos</p></blockquote>'),
        '> uno\n>\n> dos',
      );
    });

    test('la línea divisoria no se confunde con el separador de capítulos', () {
      expect(htmlToMarkdown('<p>a</p><hr><p>b</p>'), 'a\n\n* * *\n\nb');
    });

    test('texto suelto y párrafos en el mismo div, cada uno en su bloque', () {
      expect(
        htmlToMarkdown('<div>suelto<p>párrafo</p>otro suelto</div>'),
        'suelto\n\npárrafo\n\notro suelto',
      );
    });
  });

  group('tablas', () {
    test('una tabla simple es una tabla de Markdown', () {
      expect(
        htmlToMarkdown(
          '<table><thead><tr><th>Año</th><th>Hecho</th></tr></thead>'
          '<tbody><tr><td>1990</td><td>Uno</td></tr></tbody></table>',
        ),
        '| Año | Hecho |\n| --- | --- |\n| 1990 | Uno |',
      );
    });

    test(r'la barra dentro de una celda, y solo ahí, se escribe \|', () {
      // Sin la barra invertida, "1|2" partiría la celda en dos.
      expect(
        htmlToMarkdown(
          '<p>a|b</p><table><tr><th>A</th></tr><tr><td>1|2</td></tr></table>',
        ),
        'a|b\n\n| A |\n| --- |\n| 1\\|2 |',
      );
    });

    test('sin fila de encabezado, el encabezado va vacío', () {
      // Tomar la primera fila de datos como encabezado le cambiaría el
      // sentido.
      expect(
        htmlToMarkdown('<table><tr><td>a</td><td>b</td></tr></table>'),
        '|  |  |\n| --- | --- |\n| a | b |',
      );
    });

    test('una celda que ocupa dos columnas no corre a las demás', () {
      expect(
        htmlToMarkdown(
          '<table><tr><th>A</th><th>B</th><th>C</th></tr>'
          '<tr><td colspan="2">ancha</td><td>c</td></tr></table>',
        ),
        '| A | B | C |\n| --- | --- | --- |\n| ancha |  | c |',
      );
    });

    test('una tabla anidada se aplana sin perder texto', () {
      // html2md la dejaba como HTML crudo dentro de una celda.
      expect(
        htmlToMarkdown(
          '<table><tr><td>fuera<table><tr><td>dentro</td></tr></table></td>'
          '<td>otra</td></tr></table>',
        ),
        'fuera\n\n|  |\n| --- |\n| dentro |\n\notra',
      );
    });

    test('una celda con dos párrafos aplana la tabla, con los dos', () {
      expect(
        htmlToMarkdown(
          [
            '<table><caption>Cuadro 1</caption>',
            '<tr><td><p>uno</p><p>dos</p></td><td>tres</td></tr></table>',
          ].join(),
        ),
        'Cuadro 1\n\nuno\n\ndos\n\ntres',
      );
    });
  });

  group('XHTML de un libro', () {
    const prologue =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">';

    test('un <title/> vacío no se come el capítulo', () {
      // Leído como HTML, un <title/> es un título que no se cierra nunca:
      // el capítulo entero quedaba adentro del título, y se perdía.
      expect(
        xhtmlToMarkdown(
          [
            '$prologue<head><title/><script src="a.js"/></head>',
            '<body><p>El texto entero.</p></body></html>',
          ].join(),
        ),
        'El texto entero.',
      );
    });

    test('reconoce las entidades de HTML que el XML no declara', () {
      expect(
        xhtmlToMarkdown(
          '$prologue<body><p>a&nbsp;b &eacute; &amp;lt;</p></body></html>',
        ),
        'a b é &lt;',
      );
    });

    test('el salto que sigue a <pre> no es texto, igual que en HTML', () {
      expect(
        xhtmlToMarkdown('$prologue<body><pre>\n  x\n</pre></body></html>'),
        '```\n  x\n```',
      );
    });

    test('un capítulo que no es XML válido se lee como HTML', () {
      expect(
        xhtmlToMarkdown('<html><body><p>uno<br>dos</p></body></html>'),
        'uno\ndos',
      );
    });
  });

  // Lo que encontró la revisión independiente de F22: cada caso comparado
  // entero, carácter por carácter.
  group('la revisión (F22)', () {
    const prologue =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops">';

    group('un capítulo que no es XML válido', () {
      test('con <title/> y <script/> en el head no se pierde entero', () {
        // El <br> sin cerrar lo manda a leerse como HTML, y ahí el <title/>
        // no se cerraba nunca: el capítulo salía "".
        expect(
          xhtmlToMarkdown(
            [
              '$prologue<head><title/><script src="a.js"/></head>',
              '<body><p>uno<br>dos</p><p>tres</p></body></html>',
            ].join(),
          ),
          'uno\ndos\n\ntres',
        );
      });

      test('un <textarea/> o un ancla <a/> no se tragan el resto', () {
        expect(
          xhtmlToMarkdown(
            [
              '$prologue<body><p>uno<br>dos<a id="p1"/></p><textarea/>',
              '<p><img src="f.png" alt="foto"/>tres</p></body></html>',
            ].join(),
          ),
          'uno\ndos\n\n![foto](f.png)tres',
        );
      });
    });

    test('el código en línea conserva sus saltos, cada línea con su '
        'código', () {
      expect(
        htmlToMarkdown('<p>Ver <code>linea1<br>linea2</code>.</p>'),
        'Ver `linea1`\n`linea2`.',
      );
    });

    group('tablas', () {
      test('el pie va al final aunque el archivo lo escriba antes', () {
        // XHTML 1.1 exige el <tfoot> antes del <tbody>: el total quedaba
        // como primera fila.
        const table =
            '<table><thead><tr><th>Mes</th><th>Monto</th></tr></thead>'
            '<tfoot><tr><td>Total</td><td>30</td></tr></tfoot>'
            '<tbody><tr><td>Enero</td><td>10</td></tr>'
            '<tr><td>Febrero</td><td>20</td></tr></tbody></table>';
        const expected =
            '| Mes | Monto |\n| --- | --- |\n| Enero | 10 |\n'
            '| Febrero | 20 |\n| Total | 30 |';

        expect(htmlToMarkdown(table), expected);
        expect(
          xhtmlToMarkdown('$prologue<body>$table</body></html>'),
          expected,
        );
      });

      test('el encabezado va arriba aunque venga después del cuerpo', () {
        const table =
            '<table><tbody><tr><td>1</td></tr></tbody>'
            '<thead><tr><th>A</th></tr></thead></table>';

        expect(
          xhtmlToMarkdown('$prologue<body>$table</body></html>'),
          '| A |\n| --- |\n| 1 |',
        );
      });

      test('celdas sin <tr>, leídas como XML, forman una fila', () {
        expect(
          xhtmlToMarkdown(
            '$prologue<body><table><td>x</td><td>y</td></table></body></html>',
          ),
          '|  |  |\n| --- | --- |\n| x | y |',
        );
      });

      test('el texto suelto dentro de una tabla sale antes de ella, como '
          'en un navegador', () {
        final table = [
          '<table>suelto<tr><td>a</td><div>en la fila</div></tr>',
          '<p>párrafo</p></table>',
        ].join();
        const expected =
            'suelto\n\nen la fila\n\npárrafo\n\n|  |\n| --- |\n| a |';

        expect(
          xhtmlToMarkdown('$prologue<body>$table</body></html>'),
          expected,
        );
        expect(htmlToMarkdown(table), expected);
      });
    });

    group('fórmulas en MathML', () {
      final math = [
        '<p>Si <math><msup><mi>x</mi><mn>2</mn></msup></math>, ',
        '<math><mfrac><mn>1</mn><mn>2</mn></mfrac></math>, ',
        '<math><mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow>',
        '<mn>2</mn></mfrac></math>, ',
        '<math><msqrt><mi>x</mi></msqrt></math> y ',
        '<math><msub><mi>H</mi><mn>2</mn></msub></math></p>',
      ].join();
      const mathMl = 'http://www.w3.org/1998/Math/MathML';
      const expected = 'Si x<sup>2</sup>, 1/2, (a+b)/2, √(x) y H<sub>2</sub>';

      test('se escriben como se leen, sin aplanarse', () {
        // Antes: "Si x2, 12, a+b2, x y H2".
        expect(htmlToMarkdown(math), expected);
        expect(
          xhtmlToMarkdown(
            '$prologue<body>'
            '${math.replaceAll('<math>', '<math xmlns="$mathMl">')}'
            '</body></html>',
          ),
          expected,
        );
      });

      test('las anotaciones no repiten la fórmula', () {
        final annotated = [
          '<p><math><semantics><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow>',
          '<annotation encoding="application/x-tex">a+b</annotation>',
          '<annotation-xml encoding="MathML-Content"><apply><plus/>',
          '<ci>a</ci><ci>b</ci></apply></annotation-xml>',
          '</semantics></math></p>',
        ].join();

        expect(htmlToMarkdown(annotated), 'a+b');
        expect(
          xhtmlToMarkdown('$prologue<body>$annotated</body></html>'),
          'a+b',
        );
      });
    });

    group('las marcas que cruzan un <br>', () {
      test('una negrita de dos párrafos cortos se marca en cada línea', () {
        expect(
          htmlToMarkdown('<p><b>uno<br><br>dos</b></p>'),
          '**uno**\n\n**dos**',
        );
      });

      test('en un título, cada línea con su almohadilla y su negrita', () {
        expect(
          htmlToMarkdown('<h2><b>Capítulo 1<br>El comienzo</b></h2>'),
          '## **Capítulo 1**\n## **El comienzo**',
        );
      });

      test('un enlace partido es un enlace en cada línea', () {
        expect(
          htmlToMarkdown('<p><a href="x.html">uno<br>dos</a></p>'),
          '[uno](x.html)\n[dos](x.html)',
        );
      });
    });

    group('listas', () {
      test('un ítem con dos párrafos los separa con una línea en blanco', () {
        expect(
          htmlToMarkdown('<ul><li><p>a</p><p>b</p></li><li>c</li></ul>'),
          '- a\n\n  b\n- c',
        );
      });

      test('el texto que sigue a una sublista no se le pega', () {
        expect(
          htmlToMarkdown('<ul><li>a<ul><li>b</li></ul>c</li></ul>'),
          '- a\n  - b\n\n  c',
        );
      });

      test('lo anidado llega al ancho del marcador', () {
        expect(
          htmlToMarkdown('<ol><li>a<ul><li>b</li></ul></li></ol>'),
          '1. a\n   - b',
        );
        // Una sublista puesta directo en la lista, sin su <li>.
        expect(
          htmlToMarkdown(
            '<ol start="9"><li>a</li><li>b</li><ul><li>c</li></ul></ol>',
          ),
          '9. a\n10. b\n    - c',
        );
      });
    });

    test('el tachado queda marcado', () {
      // Sin la marca, "Precio: 100 80 €" dice otra cosa.
      expect(
        htmlToMarkdown(
          '<p>Precio: <del>100</del> 80 €, <s>viejo</s> y '
          '<strike>antiguo</strike></p>',
        ),
        'Precio: ~~100~~ 80 €, ~~viejo~~ y ~~antiguo~~',
      );
    });

    group('los bordes de una marca', () {
      test('el espacio duro queda afuera', () {
        expect(
          htmlToMarkdown('<p>a<b>&nbsp;negrita&nbsp;</b>b</p>'),
          'a\u00A0**negrita**\u00A0b',
        );
      });

      test('la puntuación pegada a una letra de afuera queda afuera', () {
        expect(
          htmlToMarkdown(
            '<p><i>hola,</i>mundo y palabra<b>¡hola!</b> y <i>dijo,</i> '
            'nada</p>',
          ),
          '*hola*,mundo y palabra¡**hola!** y *dijo,* nada',
        );
      });

      test('dos marcas iguales seguidas son una sola', () {
        expect(
          htmlToMarkdown('<p><i>pala</i><i>bra</i> y <b>o</b><b>tra</b></p>'),
          '*palabra* y **otra**',
        );
      });
    });

    test(r'el XHTML con saltos de Windows no deja \r en el texto', () {
      expect(
        xhtmlToMarkdown(
          '$prologue\r\n<body>\r\n<pre>\r\n  x\r\n  y\r\n</pre>\r\n'
          '<p>uno\r\ndos</p></body></html>',
        ),
        '```\n  x\n  y\n```\n\nuno dos',
      );
    });

    test('un atributo de otro espacio de nombres no pisa al de XHTML', () {
      // `epub:type` pisaba al `type` de la lista, que perdía sus letras.
      expect(
        xhtmlToMarkdown(
          [
            '$prologue<body><ol type="a" epub:type="list">',
            '<li>x</li><li>y</li></ol></body></html>',
          ].join(),
        ),
        'a. x\nb. y',
      );
    });

    group('enlaces que Markdown no puede encerrar', () {
      test('un corchete sin pareja en el texto va como HTML en línea', () {
        expect(
          htmlToMarkdown(
            [
              '<p><a href="n.html">ver [1</a> y ',
              '<a href="m.html">nota [2]</a></p>',
            ].join(),
          ),
          '<a href="n.html">ver [1</a> y [nota [2]](m.html)',
        );
      });

      test('una dirección con < o > va como HTML en línea', () {
        expect(
          htmlToMarkdown('<p><a href="a b&lt;c&gt;&amp;d">t</a></p>'),
          '<a href="a b<c>&amp;d">t</a>',
        );
      });

      test('los espacios de una dirección no se colapsan', () {
        expect(
          htmlToMarkdown('<p><a href="la  nota.html">ver</a></p>'),
          '[ver](<la  nota.html>)',
        );
      });
    });

    group('formularios, ruby e imágenes en código', () {
      test('las opciones de una lista desplegable no se pegan', () {
        expect(
          htmlToMarkdown(
            '<p><select><option>Uno</option><option>Dos</option></select></p>',
          ),
          'Uno\nDos',
        );
      });

      test('un campo muestra lo que tiene escrito; uno oculto, nada', () {
        expect(
          htmlToMarkdown(
            '<p>Nombre: <input value="Ana"><input type="hidden" '
            'value="x"></p>',
          ),
          'Nombre: Ana',
        );
      });

      test('la lectura de un ruby va entre paréntesis, una sola vez', () {
        expect(
          xhtmlToMarkdown(
            '$prologue<body><p><ruby>漢<rt>kan</rt></ruby></p></body></html>',
          ),
          '漢(kan)',
        );
        expect(
          htmlToMarkdown(
            '<p><ruby>漢<rp>(</rp><rt>kan</rt><rp>)</rp></ruby></p>',
          ),
          '漢(kan)',
        );
      });

      test('una imagen dentro de <pre> deja su texto alternativo', () {
        expect(
          htmlToMarkdown('<pre>a <img src="b.png" alt="β"> c</pre>'),
          '```\na β c\n```',
        );
      });
    });

    test('las entidades que declara el capítulo se expanden', () {
      expect(
        xhtmlToMarkdown(
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!DOCTYPE html [<!ENTITY autor "Cervantes">]>\n'
          '<html xmlns="http://www.w3.org/1999/xhtml">\n'
          '<body><p>Por &autor; &amp; otros&nbsp;más.</p></body></html>',
        ),
        'Por Cervantes & otros\u00A0más.',
      );
    });
  });
}
