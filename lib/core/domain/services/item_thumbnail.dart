import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/storage/file_format.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/util/youtube_url.dart';

/// Qué mostrar en la vista previa de un elemento: una tarjeta del grafo, una
/// fila de la biblioteca, cualquier lugar que necesite una portada.
///
/// Tres formas y no una imagen anulable: "no hay nada que mostrar" es un
/// resultado tan válido como los otros dos, y una imagen `null` lo
/// confundiría con "todavía no se resolvió" mientras el `FutureProvider`
/// que la trae sigue cargando.
sealed class ItemThumbnail {
  const ItemThumbnail();
}

/// Bytes ya decodificables con `Image.memory`: la foto original de una
/// imagen guardada, o la primera página de un PDF ya renderizada.
class ItemThumbnailBytes extends ItemThumbnail {
  const ItemThumbnailBytes(this.bytes);

  final Uint8List bytes;
}

/// Una miniatura que vive en la web y hay que pedir por red: la miniatura
/// pública de un video de YouTube.
class ItemThumbnailUrl extends ItemThumbnail {
  const ItemThumbnailUrl(this.url);

  final String url;
}

/// Nada que mostrar: la tarjeta cae en su ícono de siempre.
class ItemThumbnailNone extends ItemThumbnail {
  const ItemThumbnailNone();
}

/// Renderiza la primera página de un PDF como PNG, a tamaño de miniatura.
/// Inyectado para poder probar el resolver sin abrir PDFium de verdad —el
/// mismo criterio que `PdfEngineInitializer` en `PdfParser`.
typedef RenderPdfFirstPage = Future<Uint8List?> Function(Uint8List pdfBytes);

/// Decide y trae la vista previa de un elemento para mostrarlo con portada.
///
/// Solo cubre los casos baratos: una imagen ya guardada se lee tal cual, la
/// miniatura de YouTube es una URL pública conocida a partir del ID del
/// video —sin pedirle nada a la API de YouTube—, y un PDF se renderiza —su
/// primera página, a tamaño chico— con el mismo motor que ya usa
/// `PdfParser` para el OCR de páginas escaneadas.
///
/// Un documento que no sea PDF (`.docx`, `.epub`, un audio, una página web)
/// se queda sin miniatura a propósito: generarle una implicaría abrir un
/// motor de renderizado distinto por formato, un costo que no se paga solo
/// para una vista previa chica.
class ItemThumbnailResolver {
  const ItemThumbnailResolver({
    required FileStore files,
    required RenderPdfFirstPage renderPdfFirstPage,
  }) : _files = files,
       _renderPdfFirstPage = renderPdfFirstPage;

  final FileStore _files;
  final RenderPdfFirstPage _renderPdfFirstPage;

  Future<ItemThumbnail> resolve(KnowledgeItem item) async {
    switch (item.source.kind) {
      case SourceKind.image:
        return _fromOriginalFile(item);
      case SourceKind.document:
        return _fromPdfFirstPage(item);
      case SourceKind.youtube:
        return _fromYouTubeThumbnail(item);
      case SourceKind.webPage:
      case SourceKind.socialPost:
      case SourceKind.audio:
      case SourceKind.video:
      case SourceKind.manualNote:
        return const ItemThumbnailNone();
    }
  }

  Future<ItemThumbnail> _fromOriginalFile(KnowledgeItem item) async {
    final path = item.source.originalFilePath;
    if (path == null) return const ItemThumbnailNone();

    final bytes = await _files.read(path);
    return bytes == null
        ? const ItemThumbnailNone()
        : ItemThumbnailBytes(bytes);
  }

  Future<ItemThumbnail> _fromPdfFirstPage(KnowledgeItem item) async {
    final path = item.source.originalFilePath;
    if (path == null) return const ItemThumbnailNone();

    final bytes = await _files.read(path);
    if (bytes == null) return const ItemThumbnailNone();

    final format = detectFileFormat(bytes, name: p.basename(path));
    if (format != FileFormat.pdf) return const ItemThumbnailNone();

    final page = await _renderPdfFirstPage(bytes);
    return page == null ? const ItemThumbnailNone() : ItemThumbnailBytes(page);
  }

  ItemThumbnail _fromYouTubeThumbnail(KnowledgeItem item) {
    final url = item.source.url;
    if (url == null) return const ItemThumbnailNone();

    final uri = Uri.tryParse(url);
    final videoId = uri == null ? null : YouTubeUrl.videoIdOf(uri);
    if (videoId == null) return const ItemThumbnailNone();

    return ItemThumbnailUrl('https://i.ytimg.com/vi/$videoId/mqdefault.jpg');
  }
}
