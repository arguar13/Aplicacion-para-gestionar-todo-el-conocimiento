/// Qué clase de cosa dijo la persona que «no era» (F27): ver `AiRejections`.
enum AiRejectionKind {
  /// Un vínculo entre dos elementos, de un tipo.
  relation,

  /// Un valor de propiedad —un tema, una etiqueta— en un elemento.
  property,

  /// Una tarjeta de repaso de un elemento, por su pregunta.
  flashcard,
}
