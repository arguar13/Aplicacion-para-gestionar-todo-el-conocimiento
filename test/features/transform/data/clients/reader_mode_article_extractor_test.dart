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

  group('páginas que no son artículos', () {
    test('una portada con puros enlaces devuelve null', () {
      const homepage = '''
<html><body>
  <nav><a href="/a">Uno</a><a href="/b">Dos</a><a href="/c">Tres</a></nav>
  <ul><li><a href="/1">Nota 1</a></li><li><a href="/2">Nota 2</a></li></ul>
</body></html>
''';

      expect(extractor.extract(homepage, baseUri: baseUri), isNull);
    });

    test('una página con muy poco texto devuelve null: no era un artículo', () {
      // El algoritmo siempre devuelve algo si encuentra texto. El umbral de
      // longitud es lo que evita guardar cuatro palabras sueltas como si
      // fueran el contenido archivado.
      const tiny = '<html><body><p>Hola.</p></body></html>';

      expect(extractor.extract(tiny, baseUri: baseUri), isNull);
    });

    test('HTML vacío o roto devuelve null en vez de estallar', () {
      expect(extractor.extract('', baseUri: baseUri), isNull);
      expect(extractor.extract('<<<no es html>>>', baseUri: baseUri), isNull);
    });
  });
}
