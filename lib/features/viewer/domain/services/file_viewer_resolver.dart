import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
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
/// `FileStore.readHead()`, no una ruta absoluta ni `dart:io` directo. La
/// diferencia importa de verdad en la web, donde `OpfsFileStore.resolve()`
/// no tiene ninguna ruta que devolver —ver esa clase—: pedirla sin
/// necesitarla de verdad rompería ahí lo que en cualquier otra plataforma
/// nunca hacía falta.
class FileViewerResolver {
  const FileViewerResolver({required FileStore files}) : _files = files;

  final FileStore _files;

  Future<ResolvedViewer> resolve(KnowledgeItem item) async {
    final relativePath = item.source.originalFilePath;
    if (relativePath == null) return const NoResolvedViewer();

    switch (item.source.kind) {
      case SourceKind.image:
        return ImageResolvedViewer(await _files.resolve(relativePath));

      case SourceKind.audio:
      case SourceKind.video:
        return MediaResolvedViewer(
          path: await _files.resolve(relativePath),
          isVideo: item.source.kind == SourceKind.video,
        );

      case SourceKind.document:
        return _resolveDocument(item, relativePath);

      case SourceKind.webPage:
        // La página archivada es un HTML de verdad, no texto extraído.
        return WebPageResolvedViewer(await _files.resolve(relativePath));

      case SourceKind.youtube:
        // El audio es un extra sobre la transcripción (ver
        // `YouTubeTranscriptTransformer`): si se pudo bajar, se puede
        // escuchar.
        return MediaResolvedViewer(
          path: await _files.resolve(relativePath),
          isVideo: false,
        );

      case SourceKind.socialPost:
        // Como con YouTube: si `SocialPostTransformer` consiguió bajar el
        // video del reel o la publicación, se puede ver.
        return MediaResolvedViewer(
          path: await _files.resolve(relativePath),
          isVideo: true,
        );

      case SourceKind.manualNote:
        // No trae un archivo original que mostrar aparte del contenido que
        // ya se ve en el propio detalle.
        return const NoResolvedViewer();
    }
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
