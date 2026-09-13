/// En qué forma existe un contenido.
///
/// Un mismo elemento puede tener varias a la vez, y esa es la idea: un video
/// de YouTube puede guardarse como transcripción, como enlace y como imagen
/// de su miniatura sin que haya que elegir una y descartar el resto. Al
/// exportar se toma la que haga falta.
enum RenditionKind {
  /// Texto sin formato.
  plainText,

  /// Texto con formato Markdown. El formato de intercambio por defecto:
  /// lo leen Obsidian, Logseq, Notion y cualquier editor.
  markdown,

  /// Una nota armada con bloques —encabezados, listas, casilleros, citas—,
  /// al estilo de Notion. El contenido guardado es JSON: una lista de
  /// bloques codificada por `encodeContentBlocks` en `content_block.dart`,
  /// no texto plano ni Markdown. Solo la produce y la edita el usuario,
  /// nunca un transformador: no hay forma automática de saber dónde
  /// termina un párrafo y empieza el siguiente en un texto ajeno.
  blocks,

  /// HTML — típicamente la copia de una página tal como estaba el día que
  /// se guardó, con sus recursos incrustados.
  html,

  image,
  audio,
  video,
  pdf,
}
