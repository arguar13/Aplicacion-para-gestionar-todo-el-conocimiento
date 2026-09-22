/// Qué clase de cosa propone una [Suggestion].
///
/// Las cuatro vienen del modelo de datos original del refactor de
/// organización —secciones 4 y 9 a 12 del encargo—, aunque F4 solo genera
/// `property`: modelar las cuatro ahora evita otra migración de esquema
/// cuando F5 (relaciones) y F7 (deduplicación) las necesiten.
enum SuggestionKind {
  /// Un valor de propiedad para clasificar un elemento — F4.
  property,

  /// Un vínculo entre dos elementos — F5, motor de relaciones.
  relation,

  /// Dos elementos que podrían ser el mismo — F7, deduplicación.
  duplicate,

  /// Una tarjeta de repaso propuesta a partir del contenido — ya existe
  /// como `FlashcardDraft` efímero; modelado acá para una futura cola
  /// persistente, sin generador todavía.
  flashcard,

  /// Los datos bibliográficos leídos del PDF, la página o YouTube — F15.
  metadata,
}
