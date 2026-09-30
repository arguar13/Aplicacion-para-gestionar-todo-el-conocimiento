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
///
/// **Un artículo corto se guarda igual (F22).** Antes, por debajo de 250
/// caracteres se decía que no había artículo, y el transformador lanzaba
/// antes de archivar: de un aviso breve, una nota de dos párrafos o una
/// página de definiciones no quedaba ni el texto ni la página. Ahora todo
/// texto que el algoritmo encuentre se devuelve; `null` queda solo para una
/// página sin una letra.
///
/// **El límite que queda, y que es del algoritmo.** Readability, en un
/// artículo largo, limpia "condicionalmente" tablas, listas y `<div>` que
/// parecen navegación —muchos enlaces, pocas comas, más ítems que
/// párrafos—, y saca el `<h1>` que repite el título (que igual queda como
/// título del elemento). Casi siempre acierta, pero una lista de
/// referencias o una tabla con enlaces puede caer. No se reescribe acá: el
/// paquete no deja apagar esa limpieza, y el resguardo ya existe, porque la
/// página entera queda archivada como el archivo original de la fuente. En
/// un artículo de menos de 500 caracteres, en cambio, el algoritmo vuelve a
/// intentar sin esa limpieza, así que lo corto sale con sus tablas y listas.
class ReaderModeArticleExtractor implements ArticleExtractor {
  const ReaderModeArticleExtractor();

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
    if (text.isEmpty) return null;

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
