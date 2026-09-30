/// Qué visor le corresponde al archivo original de un elemento, ya resuelto
/// —con la ruta absoluta en mano y el formato identificado— pero sin decidir
/// todavía **cómo** mostrarlo.
///
/// Separado en un tipo de datos propio, en vez de que cada lugar que
/// necesita esto repita el mismo `switch` sobre `SourceKind` y vuelva a leer
/// el archivo para reconocer el formato: `FileViewerResolver.resolve` lo
/// calcula una sola vez, y tanto `openDocumentViewer` —que empuja una
/// pantalla nueva— como `EmbeddedFileViewer` —que lo embebe directo en el
/// detalle— parten del mismo resultado.
sealed class ResolvedViewer {
  const ResolvedViewer();
}

/// Nada que mostrar: sin archivo original, un formato que no se pudo
/// reconocer, o un documento sin ninguna forma de texto todavía.
class NoResolvedViewer extends ResolvedViewer {
  const NoResolvedViewer();
}

class ImageResolvedViewer extends ResolvedViewer {
  const ImageResolvedViewer(this.path);

  final String path;
}

/// Audio o video, según [isVideo] —solo decide qué carátula mostrar
/// mientras no hay una pista de video real, ver `MediaPlayerView`—.
class MediaResolvedViewer extends ResolvedViewer {
  const MediaResolvedViewer({required this.path, required this.isVideo});

  final String path;
  final bool isVideo;
}

class PdfResolvedViewer extends ResolvedViewer {
  const PdfResolvedViewer(this.path);

  final String path;
}

/// La vista previa de un video de YouTube: su miniatura, para tocar y
/// abrir el video de verdad —en la app de YouTube o en el navegador—, no
/// un reproductor propio.
///
/// Aparte de [MediaResolvedViewer] a propósito: lo que hay para mostrar acá
/// no es un archivo que este elemento tenga guardado —el audio que
/// `YouTubeTranscriptTransformer` baja es solo para transcribir, nunca fue
/// pensado como algo que alguien fuera a escuchar desde la app—, sino el
/// video original, completo, que ya existe en YouTube. Por eso no depende
/// de que ese audio se haya podido bajar: [videoId] sale de [url], que
/// cualquier elemento de este origen tiene siempre.
class YoutubeEmbedResolvedViewer extends ResolvedViewer {
  const YoutubeEmbedResolvedViewer({required this.videoId, required this.url});

  final String videoId;
  final String url;
}

/// La página archivada, tal como quedó guardada —con sus imágenes y sus
/// estilos incrustados—, no el Markdown que ya se ve en el detalle.
class WebPageResolvedViewer extends ResolvedViewer {
  const WebPageResolvedViewer(this.path);

  final String path;
}

/// El contenido ya extraído de un DOCX, un EPUB o texto suelto: no hay un
/// visor de archivo que mostrar aparte —esto **es** el archivo, convertido a
/// texto—, así que lo que se resuelve es el contenido en sí, listo para el
/// modo de lectura paginado.
class TextResolvedViewer extends ResolvedViewer {
  const TextResolvedViewer(this.content, {this.markdown = true});

  final String content;

  /// Si [content] es Markdown —un DOCX o un EPUB convertidos, un `.md`— o
  /// texto tal cual, como un `.txt` (F22).
  final bool markdown;
}
