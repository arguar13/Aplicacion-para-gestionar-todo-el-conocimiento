import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/clients/reader_mode_article_extractor.dart';

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
}
