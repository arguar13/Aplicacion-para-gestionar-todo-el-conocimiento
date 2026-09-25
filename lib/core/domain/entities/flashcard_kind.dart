/// La forma de una tarjeta de repaso (F20).
///
/// El programador SM-2 y `review_log` son indiferentes a esto —repasan y
/// registran por igual, sin leer `front`/`back` ni las opciones—: es la
/// presentación la que cambia según el valor.
enum FlashcardKind {
  /// Pregunta y respuesta libres: lo que `Flashcard` siempre fue, antes de
  /// F20. El valor por defecto de toda tarjeta que ya existía.
  freeRecall,

  /// Opción múltiple: la pregunta va en `front`, y las opciones —una
  /// correcta, el resto distractores, cada una con su propia procedencia—
  /// viven en `flashcard_options`.
  multipleChoice,

  /// Verdadero o falso: `front` es la afirmación, `back` explica por qué es
  /// verdadera o falsa. No usa `flashcard_options` —dos opciones fijas no
  /// necesitan una tabla propia—: la procedencia es la que `Flashcard` ya
  /// tiene.
  trueFalse,
}
