/// Qué le pidieron a una pasada de la IA (`ai_runs.scope`, v37).
enum AiRunScope {
  /// Organizar el elemento: vínculos, tarjetas, temas, etiquetas, propiedades,
  /// el Atlas (F27). Lo de siempre, y lo que tienen todas las pasadas de antes
  /// de v37.
  organize,

  /// Solo tarjetas de repaso (F30): el ✨ «Crear tarjetas con IA» de Repasar o
  /// de un cuaderno. No organizó el elemento, así que para la cola sigue
  /// pendiente: la biblioteca que ya existía se organiza igual con el cargador.
  flashcards,
}
