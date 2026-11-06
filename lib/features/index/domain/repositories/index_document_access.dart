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

/// Lo que se sabe de un documento al hacer algo con una de sus entradas.
typedef IndexDocumentFacts = ({
  /// El título del documento, de donde ya está.
  String title,

  /// Su copia del original; `null` si no guardó ninguna.
  IndexOriginalKind? original,
});

/// Lo que el Índice necesita de un documento procesado para lo que se hace
/// con una entrada (F46, paso 4) —abrirla en el original, preguntarle al chat
/// por ella—, leído recién cuando se lo pide: el Índice no carga nada de esto
/// mientras se lo recorre.
abstract interface class IndexDocumentAccess {
  /// El título de [documentId] y qué copia del original guarda, o `null` si
  /// el documento ya no está.
  Future<IndexDocumentFacts?> factsOf(String documentId);

  /// El texto propio de [documentId] —sus páginas de «Texto» una detrás de la
  /// otra, el mismo con que el Índice ubica cada capítulo—, o `null` si no
  /// tiene o no se pudo leer.
  Future<String?> textOf(String documentId);
}
