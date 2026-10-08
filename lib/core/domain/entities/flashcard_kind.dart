/// La forma de una tarjeta de repaso (F20, F31).
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

  /// Huecos para completar (F31): `front` guarda el TEXTO ENTERO con sus huecos
  /// marcados (`El {{c1::Imperio romano}} cayó en {{c2::476}}`), `back` un
  /// complemento opcional (puede quedar vacío) y `cloze_index` dice cuál de los
  /// huecos tapa ESTA tarjeta (1, 2…). Cada hueco es una tarjeta distinta, con
  /// su propio calendario, y las de un mismo texto comparten `group_id`.
  cloze,

  /// «Escribí la respuesta» (F31): como `freeRecall`, pero en lugar de revelar
  /// la respuesta, la persona la escribe y se la compara con `back`. El
  /// calendario es el mismo; solo cambia cómo se contesta.
  typedAnswer,
}
