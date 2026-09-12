import 'package:reader_mode/reader_mode.dart' as reader;
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';

/// [ArticleExtractor] sobre `reader_mode`, un port en Dart del algoritmo
/// Readability de Mozilla — el mismo que usa el modo lectura de Firefox.
///
/// Se eligió después de probarlo contra una página armada como las de
/// verdad: navegación, banner de publicidad, barra lateral con "lo más
/// leído", formulario de boletín, comentarios y pie de página alrededor del
/// artículo. Conservó los cuatro párrafos del texto y descartó los cinco
/// bloques de ruido, además de sacar el autor de la metaetiqueta.
///
/// Esa prueba importó porque el paquete es joven y casi sin adopción: su
/// puntaje perfecto en pub.dev mide que esté bien empaquetado —documentado,
/// con tests, sin código obsoleto— y no que funcione con sitios reales. Por
/// eso también queda detrás de [ArticleExtractor]: si falla con alguna clase
/// de páginas, se cambia acá y nada más se entera.
class ReaderModeArticleExtractor implements ArticleExtractor {
  const ReaderModeArticleExtractor();

  /// Por debajo de esto, lo extraído no es un artículo.
  ///
  /// El algoritmo siempre devuelve *algo* si encuentra texto, y en una
  /// portada o un listado ese algo es un amasijo de fragmentos de menú.
  /// Guardar eso sería peor que no guardar contenido: ensucia la búsqueda y
  /// hace creer que el artículo se archivó cuando no.
  static const _minimumArticleLength = 250;

  @override
  ExtractedArticle? extract(String html, {required Uri baseUri}) {
    // `reader_mode` trae dos parsers: `ParserType.jsdom` (el default), un
    // parser de HTML escrito a mano para este paquete, y `ParserType.html`,
    // que delega en `package:html` —el parser HTML5 estándar de Dart, el
    // mismo que ya usa `WebPageAdapter` en el resto del proyecto—. El
    // primero no tolera el HTML real de páginas grandes y con muchos años
    // de historia como Wikipedia: revienta con errores del estilo
    // "expected '</main>' and got '</div>'" apenas encuentra una etiqueta
    // que no cierra exactamente como él espera, y `parse()` devuelve
    // `null` en vez de un artículo. Un parser HTML5 de verdad —que
    // entiende elementos vacíos y cierre implícito de etiquetas, igual que
    // un navegador— no tiene ese problema.
    final article = reader.parse(
      html,
      baseUri: baseUri.toString(),
      parser: reader.ParserType.html,
    );
    if (article == null) return null;

    final text = article.textContent.trim();
    if (text.length < _minimumArticleLength) return null;

    final content = article.content.trim();
    if (content.isEmpty) return null;

    return ExtractedArticle(
      contentHtml: content,
      textContent: text,
      title: article.title.trim(),
      byline: article.byline?.trim(),
      siteName: article.siteName?.trim(),
    );
  }
}
