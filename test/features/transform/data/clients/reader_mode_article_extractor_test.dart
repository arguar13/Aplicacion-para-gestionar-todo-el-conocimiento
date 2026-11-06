import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';

/// Verifica el extractor contra HTML armado como el de un sitio real.
///
/// Estas pruebas existen por una razón concreta: el paquete que hay debajo es
/// joven y casi sin adopción, y su puntaje perfecto en pub.dev mide que esté
/// bien empaquetado —documentado, con tests, sin código obsoleto— y no que
/// funcione con páginas de verdad. La decisión de usarlo se tomó corriendo
/// exactamente esto, y queda acá para que siga valiendo: si una versión
/// futura del paquete empeora, o si algún día se reemplaza por otro, el que
/// entre tiene que pasar las mismas pruebas.
void main() {
  const extractor = ReaderModeArticleExtractor();
  final baseUri = Uri.parse('https://ejemplo.org/blog/un-articulo');

  const realisticPage = '''
<!DOCTYPE html>
<html lang="es">
<head>
  <title>La estructura de las revoluciones | Revista Ejemplo</title>
  <meta name="author" content="Ana Ejemplo">
</head>
<body>
  <header class="site-header">
    <nav><a href="/">Inicio</a><a href="/temas">Temas</a><a href="/suscribite">Suscribite</a></nav>
  </header>
  <div class="ad-banner">PUBLICIDAD: comprá ya nuestro curso online de tres meses</div>
  <div class="layout">
    <aside class="sidebar">
      <h3>Lo más leído</h3>
      <ul><li><a href="/a">Otro artículo</a></li><li><a href="/b">Y otro más</a></li>
      <li><a href="/c">Tercero</a></li><li><a href="/d">Cuarto</a></li></ul>
      <div class="newsletter">Suscribite al boletín semanal para no perderte nada</div>
    </aside>
    <article class="post-content">
      <h1>La estructura de las revoluciones científicas</h1>
      <p>Kuhn sostiene que la ciencia no avanza acumulando verdades una sobre otra, sino a través de rupturas que reorganizan por completo el modo en que una comunidad entiende su campo de estudio.</p>
      <p>Un paradigma, en su vocabulario, no es solamente una teoría: es el conjunto de prácticas, instrumentos y preguntas que una comunidad científica da por sentados mientras trabaja. Durante los períodos de ciencia normal, los investigadores resuelven rompecabezas dentro de ese marco sin cuestionarlo.</p>
      <p>La crisis llega cuando las anomalías se acumulan y dejan de poder explicarse con los recursos disponibles. Entonces aparece un candidato nuevo, y la comunidad se divide entre quienes lo adoptan y quienes lo resisten.</p>
      <p>Lo interesante del argumento es que la elección entre paradigmas no se resuelve solo con datos. Los criterios para evaluar la evidencia forman parte de aquello que está en disputa, lo que vuelve la decisión irreductible a un procedimiento puramente lógico.</p>
    </article>
  </div>
  <section class="comments">
    <h3>42 comentarios</h3>
    <div class="comment">Excelente nota, muy clara.</div>
    <div class="comment">No estoy de acuerdo con el tercer párrafo.</div>
  </section>
  <footer><p>2026 Revista Ejemplo. Todos los derechos reservados</p></footer>
</body>
</html>
''';

  group('sobre una página realista', () {
    test('conserva el artículo completo', () {
      final article = extractor.extract(realisticPage, baseUri: baseUri);

      expect(article, isNotNull);
      for (final fragment in [
        'Kuhn sostiene',
        'rompecabezas',
        'anomalías',
        'irreductible',
      ]) {
        expect(
          article!.textContent,
          contains(fragment),
          reason: 'se perdió "$fragment" del artículo',
        );
      }
    });

    test('descarta todo lo que rodea al artículo', () {
      final article = extractor.extract(realisticPage, baseUri: baseUri);

      for (final noise in [
        'PUBLICIDAD',
        'Lo más leído',
        'Suscribite al boletín',
        '42 comentarios',
        'Todos los derechos',
      ]) {
        expect(
          article!.textContent,
          isNot(contains(noise)),
          reason: 'se coló "$noise", que no es parte del artículo',
        );
      }
    });

    test('saca el autor de la metaetiqueta', () {
      final article = extractor.extract(realisticPage, baseUri: baseUri);

      expect(article!.byline, contains('Ana Ejemplo'));
    });
  });

  group('los controles de una wiki no son su texto (F46)', () {
    // Visto en el emulador con la biblioteca de ejemplo: cada capítulo de
    // un artículo de Wikipedia llegaba al lector con un renglón «[editar]»
    // debajo. MediaWiki marca ese enlace como control (`.mw-editsection`).
    const wikiPage = '''
<!DOCTYPE html>
<html lang="es">
<head><title>Edad Media - Wikipedia</title></head>
<body>
  <main>
    <h1>Edad Media</h1>
    <p>La Edad Media es el período histórico de la civilización occidental comprendido entre el siglo V y el XV, que la historiografía tradicional cuenta desde la caída del Imperio romano de Occidente.</p>
    <div class="mw-heading mw-heading4"><h4 id="cristiandad">La cristiandad latina y los bárbaros</h4><span class="mw-editsection"><span class="mw-editsection-bracket">[</span><a href="/w/index.php?action=edit&amp;section=5">editar</a><span class="mw-editsection-bracket">]</span></span></div>
    <p>La expansión del cristianismo entre los bárbaros, el asentamiento de la autoridad episcopal en las ciudades y del monacato en los ámbitos rurales constituyeron una poderosa fuerza fusionadora de culturas.</p>
    <p>Un glosario de la época anota la abreviatura [editar] como se la escribía en los márgenes de los códices, para que conste que el artículo mismo puede decirlo.</p>
  </main>
</body>
</html>
''';

    test('el «[editar]» de cada título se va, con el título y su texto '
        'intactos', () {
      final article = extractor.extract(wikiPage, baseUri: baseUri)!;

      expect(article.contentHtml, isNot(contains('mw-editsection')));
      expect(article.contentHtml, isNot(contains('action=edit')));
      expect(
        article.textContent,
        contains('La cristiandad latina y los bárbaros'),
      );
      expect(article.textContent, contains('fuerza fusionadora'));
    });

    test('un «[editar]» escrito en el artículo mismo se queda: se saca por '
        'su marca, no por su texto', () {
      final article = extractor.extract(wikiPage, baseUri: baseUri)!;

      expect(article.textContent, contains('la abreviatura [editar] como'));
      expect('[editar]'.allMatches(article.textContent), hasLength(1));
    });
  });

  group('los capítulos de un artículo de Wikipedia llegan enteros (F46, '
      'paso 5b)', () {
    // Visto en el emulador: el Índice de Fotosíntesis salía vacío y el de
    // Imperio romano con 7 capítulos de 57. Con su control de edición
    // adentro —«[editar código · editar]», dos enlaces—, el `<div>` que
    // envuelve cada título tenía más texto de enlace que de título, y la
    // limpieza condicional de Readability lo tiraba con el título adentro.
    // El recorte es de la página real, con sus títulos tal cual.
    final page = File(
      'test/fixtures/web/wikipedia_fotosintesis_recorte.html',
    ).readAsStringSync();
    final wiki = Uri.parse('https://es.wikipedia.org/wiki/Fotos%C3%ADntesis');

    test('cada título queda, en su nivel y en su lugar', () {
      final markdown = htmlToMarkdown(
        extractor.extract(page, baseUri: wiki)!.contentHtml,
      );
      final headings = [
        for (final line in markdown.split('\n'))
          // Wikipedia une «siglo» y «XIX» con un espacio que no se corta.
          if (line.startsWith('#')) line.replaceAll('\u00a0', ' '),
      ];

      expect(headings, [
        '## Historia del estudio de la fotosíntesis',
        '### Desde la Antigua Grecia hasta el siglo XIX',
        '### Siglo XX',
        '## El cloroplasto',
        '### Desarrollo',
        '### Función',
      ]);
      // El primero va antes del texto que encabeza, no en otro lado.
      expect(
        markdown.indexOf('## Historia del estudio'),
        lessThan(markdown.indexOf('Ya en la [Antigua Grecia]')),
      );
    });

    test('sin un «[editar]» de más', () {
      final markdown = htmlToMarkdown(
        extractor.extract(page, baseUri: wiki)!.contentHtml,
      );

      expect(markdown, isNot(contains('editar')));
    });
  });

  group('el id que es el ancla del título no pesa (F46, paso 5b)', () {
    // Wikipedia le pone a cada título de `id` su mismo texto
    // («Alta_Edad_Media_(siglos_V_al_X)»), y Readability juzga el `id` por
    // sus pedazos: «media», «social». En Edad Media se iban 8 de 61.
    final page = File(
      'test/fixtures/web/wikipedia_edad_media_recorte.html',
    ).readAsStringSync();
    final wiki = Uri.parse('https://es.wikipedia.org/wiki/Edad_Media');

    test('los capítulos que dicen «Media» o «social» quedan', () {
      final markdown = htmlToMarkdown(
        extractor.extract(page, baseUri: wiki)!.contentHtml,
      );
      final headings = [
        for (final line in markdown.split('\n'))
          // Wikipedia une «siglo» y «XIX» con un espacio que no se corta.
          if (line.startsWith('#')) line.replaceAll('\u00a0', ' '),
      ];

      expect(headings, [
        '## Es impropio hablar de *Edad Media* en otras civilizaciones',
        '## El inicio de la Edad Media',
        '## Alta Edad Media (siglos V al X)',
        '### Los reinos germanorromanos (siglos V al VIII)',
        '## Plena Edad Media (siglos XI al XIII)',
        '### La expansión del sistema feudal',
        '#### Dinamismo interno: económico, social, tecnológico e intelectual',
        '#### La universidad',
        '#### Sacramentos y cohesión social. Minorías religiosas',
      ]);
    });

    test('lo que la página nombra como comentarios o para compartir se sigue '
        'yendo: ese id no es el título', () {
      const blog = '''
<!DOCTYPE html>
<html lang="es">
<head><title>Napas y lluvia | Bitácora</title></head>
<body>
  <article>
    <p>El proyecto empezó con una meta modesta: medir cuánto tarda en llegar el agua de lluvia a las napas de una cuenca chica, con instrumentos que cualquiera pudiera armar.</p>
    <h2 id="La_meta_del_proyecto,_paso_a_paso">La meta del proyecto, paso a paso</h2>
    <p>Primero se eligieron los puntos de medición, después se calibraron los sensores y, por último, se juntaron tres años de datos, con sus huecos y sus correcciones.</p>
    <h2 id="share">Compartí esta nota</h2>
    <h2 id="comments">Comments</h2>
    <p>Los resultados, publicados con sus planillas, muestran que la demora depende más del suelo que de la cantidad de lluvia, contra lo que se esperaba al empezar.</p>
  </article>
</body>
</html>
''';
      final article = extractor.extract(blog, baseUri: baseUri)!;

      expect(
        article.textContent,
        contains('La meta del proyecto, paso a paso'),
      );
      expect(article.textContent, isNot(contains('Compartí esta nota')));
      expect(article.textContent, isNot(contains('Comments')));
    });
  });

  group('unweightTitleAnchors: la regla sola', () {
    String? idAfter(String heading, {String selector = 'h2'}) {
      final document = html_parser.parse('<body>$heading</body>');
      unweightTitleAnchors(document);
      return document.querySelector(selector)!.attributes['id'];
    }

    test('el texto del título escrito como ancla se va', () {
      expect(
        idAfter(
          '<h2 id="Alta_Edad_Media_(siglos_V_al_X)">Alta Edad Media '
          '(siglos V al X)</h2>',
        ),
        isNull,
      );
      // Al estilo de GitHub y de los índices: minúscula, guiones, sin acentos.
      expect(
        idAfter(
          '<h2 id="cohesion-social-y-minorias">Cohesión social y '
          'minorías</h2>',
        ),
        isNull,
      );
      // Con dirección (`%C3%B3`) y con el número de un título repetido.
      expect(
        idAfter('<h2 id="Cohesi%C3%B3n_social">Cohesión social</h2>'),
        isNull,
      );
      expect(idAfter('<h2 id="Redes_sociales_2">Redes sociales</h2>'), isNull);
    });

    test('también el ancla vieja de MediaWiki que el título lleva adentro', () {
      expect(
        idAfter(
          '<h2 id="Cohesión_social"><span id="Cohesi.C3.B3n_social" '
          'typeof="mw:FallbackId"></span>Cohesión social</h2>',
          selector: 'span',
        ),
        isNull,
      );
    });

    test('un id que no es el texto del título se queda', () {
      expect(idAfter('<h2 id="comments">3 comentarios</h2>'), 'comments');
      expect(
        idAfter('<h2 id="related-media">Más sobre esto</h2>'),
        'related-media',
      );
      // Parecido no es igual: le sobra una palabra.
      expect(
        idAfter('<h2 id="Edad_Media_tardia">Edad Media</h2>'),
        'Edad_Media_tardia',
      );
    });

    test('un título que es solo una palabra de estructura conserva su id: '
        'no hay cómo saber si es el ancla o el nombre', () {
      expect(idAfter('<h2 id="comments">Comments</h2>'), 'comments');
      expect(idAfter('<h2 id="Media">Media</h2>'), 'Media');
      expect(idAfter('<h2 id="tags">Tags</h2>'), 'tags');
      // Una palabra que solo contiene una de esas no es una de esas.
      expect(idAfter('<h2 id="Metafísica">Metafísica</h2>'), isNull);
    });

    test('un id mal escrito como dirección no rompe nada', () {
      // Un `%` sin sus dos cifras, y bytes que no son UTF-8.
      expect(idAfter('<h2 id="100%_seguro">100% seguro</h2>'), isNull);
      expect(idAfter('<h2 id="Caf%FF">Café</h2>'), 'Caf%FF');
    });

    test('la clase no se toca: sigue pesando como siempre', () {
      final document = html_parser.parse(
        '<body><h2 id="Comentarios_de_lectores" '
        'class="comments-title">Comentarios de lectores</h2></body>',
      );
      unweightTitleAnchors(document);

      expect(
        document.querySelector('h2')!.attributes['class'],
        'comments-title',
      );
    });
  });

  group('HTML real, no el de un ejemplo prolijo', () {
    // Encontrado validando la app contra Wikipedia real, no en ninguna
    // revisión de código: `ParserType.jsdom` (el default de `reader_mode`)
    // reventaba con "expected '</main>' and got '</div>'" y devolvía
    // `null` apenas encontraba párrafos sin cerrar o etiquetas sin
    // anidar como él esperaba —algo común en páginas grandes con años de
    // historia—, tal como hace un párrafo de verdad sin `</p>` explícito.
    // Un parser HTML5 de verdad tolera exactamente esto, que es
    // justamente lo que corrige el cambio a `ParserType.html`.
    test('un párrafo sin cerrar no tira el artículo entero', () {
      const messyPage = '''
<!DOCTYPE html>
<html lang="es">
<head><title>Un artículo con HTML descuidado</title></head>
<body>
  <main>
    <div class="mw-parser-output">
      <p>Kuhn sostiene que la ciencia no avanza acumulando verdades una sobre otra, sino a través de rupturas que reorganizan por completo el modo en que una comunidad entiende su campo de estudio.
      <p>Un paradigma, en su vocabulario, no es solamente una teoría: es el conjunto de prácticas, instrumentos y preguntas que una comunidad científica da por sentado mientras trabaja, sin cuestionarlo durante los períodos de ciencia normal.
      <img src="/diagrama.png">
      <p>La crisis llega cuando las anomalías se acumulan y dejan de poder explicarse con los recursos disponibles, y aparece un candidato nuevo que reorganiza el campo entero de la disciplina.
    </div>
  </main>
</body>
</html>
''';

      final article = extractor.extract(messyPage, baseUri: baseUri);

      expect(article, isNotNull);
      expect(article!.textContent, contains('Kuhn sostiene'));
      expect(article.textContent, contains('anomalías'));
    });
  });

  // Antes, por debajo de 250 caracteres se decía que no había artículo y el
  // transformador lanzaba antes de archivar: no quedaba ni el texto ni la
  // página. Ahora lo que el algoritmo encuentre se devuelve (F22).
  group('páginas cortas o que no son artículos', () {
    test('una página con muy poco texto devuelve ese texto, no null', () {
      const tiny = '<html><body><p>Hola.</p></body></html>';

      final article = extractor.extract(tiny, baseUri: baseUri);

      expect(article?.textContent, 'Hola.');
    });

    test('una portada con puros enlaces devuelve su texto en vez de '
        'descartarlo', () {
      const homepage = '''
<html><body>
  <nav><a href="/a">Uno</a><a href="/b">Dos</a><a href="/c">Tres</a></nav>
  <ul><li><a href="/1">Nota 1</a></li><li><a href="/2">Nota 2</a></li></ul>
</body></html>
''';

      final article = extractor.extract(homepage, baseUri: baseUri);

      expect(article?.textContent, contains('Nota 1'));
      expect(article?.textContent, contains('Nota 2'));
    });

    test('solo una página sin una letra devuelve null', () {
      expect(extractor.extract('', baseUri: baseUri), isNull);
      expect(
        extractor.extract('<html><body> </body></html>', baseUri: baseUri),
        isNull,
      );
    });

    test('HTML roto no estalla: se lee como lo leería un navegador', () {
      // "<<<no es html>>>" se ve en un navegador como "<<>>": ese es su
      // texto.
      final article = extractor.extract('<<<no es html>>>', baseUri: baseUri);

      expect(article?.textContent, '<<>>');
    });
  });

  group('las direcciones salen completas (F30)', () {
    // Así escribe Wikipedia sus imágenes y enlaces: sin esquema, relativos
    // al sitio, a la carpeta y hacia arriba. Antes salían tal cual al
    // Markdown —`[![](//upload.wikimedia.org/…)](/wiki/Archivo:…)`—, que no
    // lleva a ningún lado.
    const page = '''
<html><head><title>Roma</title></head><body><article>
  <p>Roma fue fundada, según la leyenda, por Rómulo y Remo en el año 753 a. C., y llegó a ser la capital de un imperio que abarcó todo el Mediterráneo durante siglos de historia.</p>
  <p><a href="/wiki/Archivo:Coliseo.jpg"><img alt="El Coliseo" src="//upload.wikimedia.org/coliseo.jpg" srcset="//upload.wikimedia.org/coliseo-2x.jpg 2x, /img/c,3x.jpg 3x"></a></p>
  <p>Ver también <a href="../otros/foro.html">el Foro</a>, <a href="img/mapa.png">el mapa</a> y <a href="#notas">las notas</a>, o escribir a <a href="mailto:roma@ejemplo.org">la redacción</a>.</p>
  <p>El texto sigue con suficientes palabras para que el algoritmo lo tome como el artículo principal de la página, con comas, puntos y párrafos.</p>
</article></body></html>
''';

    test('sin esquema, relativas al sitio, a la carpeta y hacia arriba', () {
      final article = extractor.extract(
        page,
        baseUri: Uri.parse('https://es.wikipedia.org/wiki/sub/Roma'),
      )!;
      final html = article.contentHtml;

      expect(html, contains('src="https://upload.wikimedia.org/coliseo.jpg"'));
      expect(
        html,
        contains('href="https://es.wikipedia.org/wiki/Archivo:Coliseo.jpg"'),
      );
      expect(
        html,
        contains('href="https://es.wikipedia.org/wiki/otros/foro.html"'),
      );
      expect(
        html,
        contains('href="https://es.wikipedia.org/wiki/sub/img/mapa.png"'),
      );
      expect(
        html,
        contains(
          'srcset="https://upload.wikimedia.org/coliseo-2x.jpg 2x, '
          'https://es.wikipedia.org/img/c,3x.jpg 3x"',
        ),
      );
      // Lo que no es una dirección web, igual que antes.
      expect(html, contains('href="#notas"'));
      expect(html, contains('href="mailto:roma@ejemplo.org"'));
      expect(html, isNot(contains('"//')));
    });

    test('el <base href> de la página manda sobre su dirección', () {
      final withBase = page.replaceFirst(
        '<title>Roma</title>',
        '<title>Roma</title><base href="https://espejo.ejemplo.net/a/">',
      );
      final article = extractor.extract(
        withBase,
        baseUri: Uri.parse('https://es.wikipedia.org/wiki/Roma'),
      )!;

      expect(
        article.contentHtml,
        contains('href="https://espejo.ejemplo.net/a/img/mapa.png"'),
      );
    });

    test('un <base> que no es web no cambia nada', () {
      final withBase = page.replaceFirst(
        '<title>Roma</title>',
        '<title>Roma</title><base href="javascript:alert(1)//">',
      );
      final article = extractor.extract(
        withBase,
        baseUri: Uri.parse('https://es.wikipedia.org/wiki/Roma'),
      )!;

      expect(
        article.contentHtml,
        contains('href="https://es.wikipedia.org/wiki/img/mapa.png"'),
      );
    });

    test('las imágenes con carga diferida también se completan', () {
      const lazy = '''
<html><body><article>
  <p>Un artículo con una foto que el sitio carga recién cuando se ve en pantalla, como hacen casi todos los diarios y blogs de hoy, para que la página abra más rápido.</p>
  <p><img class="lazyload" data-src="/fotos/puerto.jpg" alt="El puerto"></p>
  <p>Más texto del artículo, con comas, puntos y suficientes palabras para que el algoritmo lo reconozca como el contenido principal.</p>
</article></body></html>
''';
      final article = extractor.extract(
        lazy,
        baseUri: Uri.parse('https://diario.ejemplo.com/notas/1'),
      )!;

      expect(
        article.contentHtml,
        contains('https://diario.ejemplo.com/fotos/puerto.jpg'),
      );
    });
  });
}
