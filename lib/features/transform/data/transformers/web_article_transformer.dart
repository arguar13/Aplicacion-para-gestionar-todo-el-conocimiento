import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/core/network/bounded_download.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/core/util/lenient_uri.dart';
import 'package:sinapsis/features/attachments/data/services/page_attachment_finder.dart';
import 'package:sinapsis/features/attachments/domain/entities/attachment.dart';
import 'package:sinapsis/features/attachments/domain/media_kind.dart';
import 'package:sinapsis/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:sinapsis/features/attachments/domain/services/linked_file_fetcher.dart';
import 'package:sinapsis/features/transform/data/documents/html_to_markdown.dart';
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
/// La conversión es la misma que la de los libros EPUB, `htmlToMarkdown`:
/// el texto del artículo va carácter por carácter, sin las barras
/// invertidas que agregaba `html2md` (F22). Ver ahí qué marcado se agrega y
/// por qué.
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
///
/// **Un enlace directo a un archivo es un archivo (F30).** Si la dirección
/// no es una página sino un PDF, un EPUB, una foto, un audio o un video, se
/// baja —acotado, de internet, sin pasar entero por memoria— y el elemento
/// pasa a ser ese archivo: un documento, una foto, un audio. El que sigue
/// —el lector de documentos, el que transcribe— le saca el texto. Lo que no
/// es ninguna de esas cosas —un `.zip`, un `.mobi`— va al «Contenido» del
/// elemento, igual que lo que enlaza una página. Un archivo que no entra en
/// el tope por elemento, o en el espacio libre, queda anotado en el
/// «Contenido» como afuera, con «Bajar el resto».
class WebArticleTransformer implements Transformer {
  const WebArticleTransformer({
    required WebPageClient client,
    required ArticleExtractor extractor,
    required PageArchiver archiver,
    required FileStore files,
    required IdGenerator ids,
    required Clock clock,
    required AppLogger logger,
    LinkedFileFetcher? fileFetcher,
    AttachmentRepository? attachments,
    int Function()? maxBytesPerItem,
    List<AttachmentCandidate> Function(String contentHtml)? attachmentFinder,
  }) : _fileFetcher = fileFetcher,
       _attachments = attachments,
       _attachmentFinder = attachmentFinder ?? findPageAttachments,
       _maxBytesPerItem = maxBytesPerItem ?? _defaultMaxBytesPerItem,
       _client = client,
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

  /// Quien baja un archivo enlazado, o `null` donde no se puede (la web).
  final LinkedFileFetcher? _fileFetcher;

  /// El «Contenido» de los elementos (F30), o `null` donde no se baja nada.
  final AttachmentRepository? _attachments;

  /// Qué ofrece el artículo para bajar. Una función de nivel superior, que
  /// viaja al otro isolate; se inyecta solo para probar que, si falla, el
  /// artículo se guarda igual.
  final List<AttachmentCandidate> Function(String contentHtml)
  _attachmentFinder;

  /// El tope por elemento de hoy (decisión E de F30), leído cada vez: se
  /// puede cambiar en Ajustes mientras la cola trabaja.
  final int Function() _maxBytesPerItem;

  static int _defaultMaxBytesPerItem() => 500 * 1024 * 1024;

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

    final String html;
    try {
      html = await _client.fetchHtml(url);
    } on NotAPageException catch (file) {
      return _captureFile(item, file, context);
    }

    // Fuera del hilo principal (F21): leer una página de cientos de KB con el
    // algoritmo del modo lectura y convertirla a Markdown es trabajo síncrono
    // que traba la interfaz mientras dura. Se puede mover porque el
    // extractor no tiene estado propio y lo que entra y sale son datos
    // simples.
    //
    // Ahí mismo se anota lo que el artículo ofrece para bajar (F30): sus
    // fotos, los archivos que enlaza y lo que incrusta. Solo si hay quien
    // lo baje: en la web no se anota nada.
    //
    // La búsqueda de lo que se puede bajar es un extra: si falla, el artículo
    // se guarda igual, sin sus archivos —y el motivo vuelve como texto, que
    // el registro de la app no viaja entre isolates—. Antes, una dirección
    // mal escrita en un enlace sin importancia le costaba a la persona el
    // artículo entero.
    final extractor = _extractor;
    final finder = _attachmentFinder;
    final findAttachments = _fileFetcher != null && _attachments != null;
    final (article, markdown, candidates, searchFailure) = await Isolate.run(
      () {
        final extracted = extractor.extract(html, baseUri: url);
        var found = const <AttachmentCandidate>[];
        String? failure;
        if (extracted != null && findAttachments) {
          try {
            found = finder(extracted.contentHtml);
            // Ver arriba: cualquier fallo, del tipo que sea, deja sin archivos
            // a la página y nada más.
            // ignore: avoid_catches_without_on_clauses
          } catch (e) {
            failure = '$e';
          }
        }
        return (
          extracted,
          extracted == null ? null : htmlToMarkdown(extracted.contentHtml),
          found,
          failure,
        );
      },
    );
    if (searchFailure != null) {
      _logger.warning(
        'No se pudo buscar lo que ofrece la página $url para bajar: '
        '$searchFailure',
      );
    }

    if (article == null || markdown == null) {
      // La página no tenía ni una letra que leer —vacía, o armada entera con
      // JavaScript—. Un texto corto ya no llega acá: se guarda (F22). Se
      // lanza para que el elemento quede como fallido y conserve su enlace,
      // que sigue sirviendo.
      throw NoArticleFoundException(url);
    }

    final now = _clock();
    // El título provisional salió de la dirección; ahora se sabe cómo se
    // llama de verdad el artículo. Se usa también para nombrar el archivo
    // de abajo: es lo que el usuario va a reconocer.
    final title = article.title?.isNotEmpty ?? false
        ? article.title!
        : item.title;

    // Lo que hay que bajar queda anotado; lo baja la cola después de
    // guardar el artículo, que no tiene por qué esperar a las fotos.
    if (candidates.isNotEmpty) await _attachments?.plan(item.id, candidates);

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
          content: markdown,
          isPrimary: true,
          createdAt: now,
        ),
      ],
    );
  }

  /// El elemento como el archivo que es (F30): ver la documentación de la
  /// clase.
  Future<KnowledgeItem> _captureFile(
    KnowledgeItem item,
    NotAPageException file,
    TransformContext context,
  ) async {
    final fetcher = _fileFetcher;
    final attachments = _attachments;
    // Donde no se bajan archivos, un archivo no es un artículo: queda como
    // antes, fallido con su enlace.
    if (fetcher == null || attachments == null) {
      throw NoArticleFoundException(file.url);
    }

    final name = file.fileName ?? lastPathSegmentOf(file.url) ?? file.url.host;
    final kind =
        mediaKindOf(contentType: file.contentType, fileName: name) ??
        RenditionKind.file;
    // Un nombre que dio el servidor es mejor título que el que se dedujo de
    // la dirección.
    final titled = file.fileName == null
        ? item
        : item.copyWith(title: p.basenameWithoutExtension(file.fileName!));
    final sourceKind = switch (kind) {
      RenditionKind.pdf || RenditionKind.document
          when isReadableDocument(
            contentType: file.contentType,
            fileName: name,
          ) =>
        SourceKind.document,
      RenditionKind.image => SourceKind.image,
      RenditionKind.audio => SourceKind.audio,
      RenditionKind.video => SourceKind.video,
      _ => null,
    };
    final candidate = AttachmentCandidate(
      url: file.url,
      kind: kind,
      position: 0,
      title: titled.title,
    );

    // Lo que no es un documento, una foto, un audio ni un video va al
    // «Contenido»: ahí se baja —y se descomprime, si es un `.zip`—.
    if (sourceKind == null) {
      await attachments.plan(item.id, [candidate]);
      return titled;
    }

    // Puede ser un video de cientos de MB: es trabajo largo.
    await context.enterLongLane();
    try {
      final fetched = await fetcher.fetch(
        file.url,
        storeId: item.source.id,
        maxBytes: _maxBytesPerItem(),
        unique: false,
        preferredName: titled.title,
        whenCancelled: context.whenCancelled,
        onProgress: (received, total) =>
            context.reportProgress(received, total ?? 0),
      );
      return titled.copyWith(
        source: titled.source.copyWith(
          kind: sourceKind,
          originalFilePath: fetched.relativePath,
        ),
      );
    } on DownloadTooLargeException catch (e) {
      await attachments.plan(item.id, [
        AttachmentCandidate(
          url: file.url,
          kind: kind,
          position: 0,
          title: titled.title,
          expectedBytes: e.declared,
        ),
      ], status: AttachmentDownloadStatus.leftOut);
      return titled;
    } on NotEnoughSpaceException {
      await attachments.plan(item.id, [
        candidate,
      ], status: AttachmentDownloadStatus.noSpace);
      return titled;
    }
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
