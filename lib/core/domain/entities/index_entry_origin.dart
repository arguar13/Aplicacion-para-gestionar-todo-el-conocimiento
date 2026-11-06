/// De dónde sale una entrada del Índice (F46, v51): un capítulo de un
/// documento procesado, el texto entero de uno que no tiene títulos, o una de
/// sus imágenes. Es la columna `processed_headings.origin`.
///
/// Las cuatro primeras son, con el mismo nombre, las de
/// `ProcessedHeadingOrigin` —de dónde sale un título que lee el paso 1—: un
/// título se guarda con su origen tal cual (`indexEntryOriginOf`). La quinta,
/// [image], es lo que agrega el Índice: las imágenes del documento, que
/// mantiene la base sola.
///
/// Se guarda por nombre (`textEnum`): renombrar un valor es una migración.
enum IndexEntryOrigin {
  /// Un marcador del PDF, con su página real (decisión B).
  bookmark,

  /// Un título del texto —`#`, `##`, `###`…—, con la página del texto
  /// procesado.
  textHeading,

  /// Un título que dejó la IA al ordenar un PDF sin marcadores (F45,
  /// decisión B), con la página del PDF donde cae si se sabe.
  aiTitle,

  /// «Texto completo»: la única entrada de un texto sin títulos, que lo abre
  /// desde el principio. Sin título propio: el nombre lo pone la pantalla.
  wholeText,

  /// Una imagen del documento, con su título (decisión E): ver
  /// `processedImageHeadingTriggers`.
  image;

  /// Si es un capítulo: algo que el texto o el PDF dicen que es un título.
  bool get isChapter =>
      this == bookmark || this == textHeading || this == aiTitle;
}
