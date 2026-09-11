/// De dónde vino algo.
///
/// Es un dato de la fuente, no del formato: un mismo `SourceKind.youtube`
/// puede terminar en una transcripción de texto, en una captura de la
/// miniatura o en las dos a la vez (ver `RenditionKind`). Separarlos es lo
/// que permite agregar una fuente nueva sin tocar las conversiones, y al
/// revés.
enum SourceKind {
  /// Video o short de YouTube.
  youtube,

  /// Cualquier página web: artículo, entrada de blog, documentación.
  webPage,

  /// Publicación de una red social — X, Bluesky, Mastodon, Instagram.
  socialPost,

  /// Documento traído por el usuario: PDF, EPUB, DOCX.
  document,

  /// Imagen o captura de pantalla.
  image,

  /// Audio: nota de voz, podcast, la pista de un video.
  audio,

  /// Video que no viene de una plataforma reconocida.
  video,

  /// Escrito por el usuario dentro de la app. No tiene enlace de origen
  /// porque el origen es la persona.
  manualNote,
}
