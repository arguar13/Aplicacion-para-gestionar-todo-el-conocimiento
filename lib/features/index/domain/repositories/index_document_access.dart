/// Qué copia del original guarda un documento procesado, para «Abrir en el
/// original» (F46, paso 4): dónde se puede abrir en el lugar de una entrada.
enum IndexOriginalKind {
  /// Un PDF: se abre en la página de la entrada.
  pdf,

  /// Una página web archivada: se abre en el título de la entrada.
  webPage,

  /// Un Word, un EPUB, un texto: el lector lo muestra desde el comienzo.
  other,
}

/// La fuente de un documento procesado en la Biblioteca (F46, paso 5c): con
/// ella, «Abrir en el original» abre el original de la Biblioteca cuando
/// Procesado no guardó su propia copia —«Pasar todo» pasa solo el texto—.
typedef IndexLibrarySource = ({
  /// El elemento de la Biblioteca.
  String itemId,

  /// Qué original tiene, para abrirlo en su visor en el lugar de la entrada;
  /// `null` si no tiene uno que se lea ahí —un audio, un video, un YouTube,
  /// una nota—: entonces se abre su ficha, que lo muestra.
  IndexOriginalKind? original,

  /// Si está en la papelera: así no se abre, se restaura primero.
  bool inTrash,
});

/// Lo que se sabe de un documento al hacer algo con una de sus entradas.
typedef IndexDocumentFacts = ({
  /// El título del documento, de donde ya está.
  String title,

  /// Su copia del original; `null` si no guardó ninguna.
  IndexOriginalKind? original,

  /// Su fuente en la Biblioteca, o `null` si ya no está (F46, paso 5c).
  IndexLibrarySource? source,
});

/// El texto propio de un documento y si es Markdown (ver
/// [IndexDocumentAccess.textOf]).
typedef IndexDocumentText = ({String content, bool markdown});

/// Lo que el Índice necesita de un documento procesado para lo que se hace
/// con una entrada (F46, paso 4) —abrirla en el original, preguntarle al chat
/// por ella—, leído recién cuando se lo pide: el Índice no carga nada de esto
/// mientras se lo recorre.
abstract interface class IndexDocumentAccess {
  /// El título de [documentId], qué copia del original guarda y su fuente en
  /// la Biblioteca, o `null` si el documento ya no está.
  Future<IndexDocumentFacts?> factsOf(String documentId);

  /// El texto propio de [documentId] —sus páginas de «Texto» una detrás de la
  /// otra, el mismo con que el Índice ubica cada capítulo— y si es Markdown,
  /// como el de su fuente (F46, paso 5e: el pasaje que viaja al chat se lee
  /// como se lee el texto); `null` si no tiene o no se pudo leer.
  Future<IndexDocumentText?> textOf(String documentId);
}
