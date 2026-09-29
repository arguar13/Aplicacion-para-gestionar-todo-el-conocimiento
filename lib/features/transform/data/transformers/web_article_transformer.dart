import 'package:html2md/html2md.dart' as html2md;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/transform/domain/archive/page_archiver.dart';
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
/// Además de extraer el artículo, archiva la página entera tal como estaba
/// —con sus imágenes y sus estilos incrustados, al modo de SingleFile— y la
/// guarda como el archivo original de la fuente. Es el seguro contra el
/// enlace que mañana da 404: aunque el artículo ya quedó a salvo en
/// Markdown, tener también la página completa preserva el diseño y
/// cualquier cosa que la extracción no haya conservado.
///
/// Que el archivado falle —una página demasiado pesada, un recurso que no
/// se pudo traer— nunca le cuesta al usuario el artículo: es un extra sobre
/// el resultado principal, no una condición para tenerlo.
class WebArticleTransformer implements Transformer {
  const WebArticleTransformer({
    required WebPageClient client,
    required ArticleExtractor extractor,
    required PageArchiver archiver,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
    required AppLogger logger,
  }) : _client = client,
       _extractor = extractor,
       _archiver = archiver,
       _files = files,
       _ids = ids,
       _clock = clock,
       _logger = logger;

  final WebPageClient _client;
  final ArticleExtractor _extractor;
  final PageArchiver _archiver;
  final FileStore _files;
  final IdGenerator _ids;
  final Clock _clock;
  final AppLogger _logger;

  /// Convierte el HTML del artículo a Markdown.
  ///
  /// `headingStyle: 'atx'` no es un detalle de gusto. Por defecto la
  /// librería escribe los encabezados de nivel 1 y 2 al estilo antiguo
  /// —subrayados con `===` y `---`— y del 3 en adelante con almohadillas,
  /// así que un mismo documento sale con dos convenciones mezcladas. Con
  /// `atx` todos quedan como `#`, `##`, `###`, que es lo que esperan
  /// Obsidian, Logseq y cualquier editor actual.
  String _toMarkdown(String html) =>
      html2md.convert(html, styleOptions: const {'headingStyle': 'atx'});

  /// Trabajo corto: una página y lo que haga falta para archivarla.
  @override
  Duration? get timeLimit => kShortTransformTimeLimit;

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
  Future<KnowledgeItem> transform(
    KnowledgeItem item, {
    TransformContext context = TransformContext.detached,
  }) async {
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
    // El título provisional salió de la dirección; ahora se sabe cómo se
    // llama de verdad el artículo. Se usa también para nombrar el archivo
    // de abajo: es lo que el usuario va a reconocer.
    final title = article.title?.isNotEmpty ?? false
        ? article.title!
        : item.title;

    final originalFilePath = await _archiveSafely(
      html,
      url: url,
      sourceId: item.source.id,
      title: title,
    );

    return item.copyWith(
      title: title,
      subtitle: article.siteName ?? item.subtitle,
      source: item.source.copyWith(
        authorName: article.byline ?? item.source.authorName,
        originalFilePath: originalFilePath ?? item.source.originalFilePath,
      ),
      renditions: [
        Rendition.text(
          id: _ids.next(),
          itemId: item.id,
          kind: RenditionKind.markdown,
          content: _toMarkdown(article.contentHtml),
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }

  /// Archiva la página y la guarda, o `null` si no se pudo.
  ///
  /// Atrapa cualquier fallo a propósito —no solo los que declara
  /// [PageArchiver], sino cualquier cosa que una implementación futura o un
  /// error de programación deje escapar—: el archivado es un extra, y el
  /// artículo que sí se extrajo no puede perderse por él.
  Future<String?> _archiveSafely(
    String html, {
    required Uri url,
    required String sourceId,
    required String title,
  }) async {
    try {
      final archived = await _archiver.archive(html, baseUri: url);
      if (archived == null) return null;

      return await _files.save(
        bytes: archived,
        suggestedName: '$title.html',
        id: sourceId,
      );
      // El archivado es un extra: cualquier fallo, del tipo que sea, se
      // registra y se sigue sin él, en vez de perder el artículo.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      _logger.warning('No se pudo archivar la página $url: $e');
      return null;
    }
  }
}
