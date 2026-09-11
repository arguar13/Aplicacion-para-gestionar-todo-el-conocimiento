import 'package:html2md/html2md.dart' as html2md;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/clients/web_page_client.dart';
import 'package:sinapsis/features/transform/domain/transformers/transformer.dart';

/// Trae una página y se queda con el artículo.
///
/// Reemplaza lo que hacían PrintFriendly y el modo lectura del navegador, con
/// una diferencia que importa: el resultado queda guardado junto al enlace
/// original, no en una pestaña que se cierra.
///
/// El contenido se guarda en Markdown y no en HTML. Son dos razones:
///
/// - El Markdown es el formato de intercambio del proyecto — lo leen
///   Obsidian, Logseq, Notion y cualquier editor de texto. Es lo que permite
///   que alguien abra su carpeta dentro de diez años, sin esta app.
/// - El índice de búsqueda toma el texto de todas las formas guardadas. Con
///   el HTML adentro, cada artículo entraría dos veces y con los nombres de
///   las etiquetas mezclados entre las palabras.
///
/// Archivar la página entera tal como estaba —con sus imágenes y sus estilos
/// incrustados, al modo de SingleFile— es otra cosa, y va como forma de
/// archivo aparte cuando exista el almacenamiento de archivos. Por ahora el
/// enlace original queda guardado en la fuente, que es lo que permite volver.
class WebArticleTransformer implements Transformer {
  const WebArticleTransformer({
    required WebPageClient client,
    required ArticleExtractor extractor,
    required IdGenerator ids,
    required Clock clock,
  }) : _client = client,
       _extractor = extractor,
       _ids = ids,
       _clock = clock;

  final WebPageClient _client;
  final ArticleExtractor _extractor;
  final IdGenerator _ids;
  final Clock _clock;

  @override
  bool canTransform(KnowledgeItem item) {
    if (item.source.kind != SourceKind.webPage) return false;
    if (item.source.url == null) return false;

    // Ya tiene contenido: no se vuelve a bajar. Sin esta comprobación, cada
    // pasada de la cola pediría de nuevo la misma página y duplicaría el
    // artículo.
    return item.renditions.isEmpty;
  }

  @override
  Future<KnowledgeItem> transform(KnowledgeItem item) async {
    final url = Uri.parse(item.source.url!);

    final html = await _client.fetchHtml(url);
    final article = _extractor.extract(html, baseUri: url);

    if (article == null) {
      // No había artículo: una portada, un listado, un panel. Se lanza en vez
      // de guardar un revoltijo de fragmentos de menú — el elemento queda
      // marcado como fallido y conserva su enlace, que sigue sirviendo.
      throw NoArticleFoundException(url);
    }

    final now = _clock();

    return item.copyWith(
      // El título provisional salió de la dirección; ahora se sabe cómo se
      // llama de verdad el artículo.
      title: article.title?.isNotEmpty ?? false ? article.title! : item.title,
      subtitle: article.siteName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: article.byline ?? item.source.authorName,
      ),
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: item.id,
          kind: RenditionKind.markdown,
          content: html2md.convert(article.contentHtml),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }
}
