import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/youtube_url.dart';
import 'package:sinapsis/features/viewer/domain/entities/resolved_viewer.dart';

/// Decide qué visor le corresponde al archivo original de un elemento.
///
/// La misma decisión que antes vivía duplicada a medias entre el botón "Ver"
/// y quien quisiera embeberlo: ahora es un solo lugar, sin `BuildContext` ni
/// nada de Flutter de por medio —solo el elemento, `FileStore` y sus
/// renditions—, así que se puede probar sola y reusar tanto para empujar
/// una pantalla nueva (`openDocumentViewer`) como para mostrarlo embebido
/// (`EmbeddedFileViewer`).
///
/// Pide una **ruta absoluta** —`FileStore.resolve()`— solo para las formas
/// que de verdad la necesitan: una imagen, un audio o video, un PDF, la
/// página archivada. Todas esas terminan en un visor de `dart:io` (o de
/// `webview_flutter`) que no sabe trabajar con otra cosa. Un documento de
/// texto —DOCX, EPUB, texto suelto— no pide ninguna: lo que hace falta ya
/// está en `item.renditions`, y reconocer si es un PDF usa
/// `FileStore.readHead()`, no una ruta absoluta ni `dart:io` directo. Un
/// video de YouTube tampoco pide ninguna: su vista previa se arma con la
/// URL original, no con ningún archivo guardado — ver el comentario de
/// `YoutubeEmbedResolvedViewer`. La diferencia importa de verdad en la web,
/// donde `OpfsFileStore.resolve()` no tiene ninguna ruta que devolver —ver
/// esa clase—: pedirla sin necesitarla de verdad rompería ahí lo que en
/// cualquier otra plataforma nunca hacía falta.
class FileViewerResolver {
  const FileViewerResolver({required FileStore files}) : _files = files;

  final FileStore _files;

  Future<ResolvedViewer> resolve(KnowledgeItem item) async {
    final relativePath = item.source.originalFilePath;

    switch (item.source.kind) {
      case SourceKind.image:
        if (relativePath == null) return const NoResolvedViewer();
        return ImageResolvedViewer(await _files.resolve(relativePath));

      case SourceKind.audio:
      case SourceKind.video:
        if (relativePath == null) return const NoResolvedViewer();
        return MediaResolvedViewer(
          path: await _files.resolve(relativePath),
          isVideo: item.source.kind == SourceKind.video,
        );

      case SourceKind.document:
        if (relativePath == null) return const NoResolvedViewer();
        return _resolveDocument(item, relativePath);

      case SourceKind.webPage:
        if (relativePath == null) return const NoResolvedViewer();
        // La página archivada es un HTML de verdad, no texto extraído.
        return WebPageResolvedViewer(await _files.resolve(relativePath));

      case SourceKind.youtube:
        // A diferencia de todos los demás casos, no depende de
        // `relativePath` en absoluto — ver el comentario de
        // `YoutubeEmbedResolvedViewer` sobre por qué.
        return _resolveYoutube(item.source.url);

      case SourceKind.socialPost:
        if (relativePath == null) return const NoResolvedViewer();
        // Si `SocialPostTransformer` consiguió bajar el video del reel o
        // la publicación, se puede ver — o, si no había video, la foto de
        // portada que bajó en su lugar.
        return _resolveDownloadedMedia(relativePath, defaultIsVideo: true);

      case SourceKind.manualNote:
        // No trae un archivo original que mostrar aparte del contenido que
        // ya se ve en el propio detalle.
        return const NoResolvedViewer();
    }
  }

  /// La vista previa de YouTube no necesita ningún archivo guardado, solo
  /// que [url] sea reconocible como un video de YouTube — algo que
  /// `YouTubeTranscriptTransformer.canTransform` ya exige para que un
  /// elemento llegue a existir con este `SourceKind` en primer lugar, así
  /// que en la práctica esto casi nunca da `NoResolvedViewer`.
  ResolvedViewer _resolveYoutube(String? url) {
    if (url == null) return const NoResolvedViewer();

    final uri = Uri.tryParse(url);
    final videoId = uri == null ? null : YouTubeUrl.videoIdOf(uri);
    if (videoId == null) return const NoResolvedViewer();

    return YoutubeEmbedResolvedViewer(videoId: videoId, url: url);
  }

  /// Para YouTube y las publicaciones sociales, el archivo bajado puede ser
  /// audio, video o —desde que `SocialPostTransformer` guarda la carátula
  /// cuando no consiguió el video— una foto sola. Sniffear el formato acá,
  /// en vez de asumirlo por el `SourceKind`, es lo que evita forzar un
  /// reproductor de video sobre una foto: se vería una pantalla negra en
  /// vez de la imagen.
  ///
  /// [defaultIsVideo] solo importa cuando el formato no se pudo reconocer
  /// —un archivo vacío, algo que se cortó a mitad de la descarga—: ahí se
  /// mantiene la suposición de siempre para ese `SourceKind`, en vez de
  /// arriesgar una decisión con nada que la respalde.
  Future<ResolvedViewer> _resolveDownloadedMedia(
    String relativePath, {
    required bool defaultIsVideo,
  }) async {
    final head = await _files.readHead(relativePath);
    final format = head == null
        ? FileFormat.unknown
        : detectFileFormat(head, name: p.basename(relativePath));

    if (format.sourceKind == SourceKind.image) {
      return ImageResolvedViewer(await _files.resolve(relativePath));
    }

    return MediaResolvedViewer(
      path: await _files.resolve(relativePath),
      isVideo: format == FileFormat.unknown
          ? defaultIsVideo
          : format.sourceKind == SourceKind.video,
    );
  }

  Future<ResolvedViewer> _resolveDocument(
    KnowledgeItem item,
    String relativePath,
  ) async {
    final head = await _files.readHead(relativePath);
    final format = head == null
        ? FileFormat.unknown
        : detectFileFormat(head, name: p.basename(relativePath));

    // Recién acá, con el formato ya confirmado como PDF, hace falta la ruta
    // absoluta que pide el visor de verdad — ver el comentario de la clase.
    if (format == FileFormat.pdf) {
      return PdfResolvedViewer(await _files.resolve(relativePath));
    }

    // Para el resto de los documentos —DOCX, EPUB, texto suelto— lo que se
    // resuelve es el contenido que ya extrajo el transformador
    // correspondiente: no hay razón para volver a leer el archivo si ya se
    // sabe qué dice.
    final rendition = item.renditions
        .whereType<TextRendition>()
        .where((r) => r.isPrimary)
        .firstOrNull;
    if (rendition == null || rendition.content.trim().isEmpty) {
      return const NoResolvedViewer();
    }

    return TextResolvedViewer(rendition.content);
  }
}
