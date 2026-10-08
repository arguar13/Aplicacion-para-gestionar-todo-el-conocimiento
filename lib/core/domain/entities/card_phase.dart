/// En qué etapa del calendario de repaso está una tarjeta (F31, decisión 69).
///
/// No se guarda en la tarjeta: se DEDUCE de sus campos (`Flashcard.phase`),
/// para que lo ya programado antes de F31 tenga etapa sin migrar nada. Sí se
/// guarda, como foto, en cada fila de `review_log` (`phase_before`): con eso se
/// cuentan las nuevas y los repasos del día, y se sabe de qué etapa partió un
/// repaso al deshacerlo.
enum CardPhase {
  /// Nunca se contestó: sin pasos, sin intervalo, sin repasos.
  newCard,

  /// Una tarjeta nueva que se está aprendiendo: recorre los pasos cortos
  /// (1 min, 10 min) antes de pasar a repasarse en días.
  learning,

  /// Una tarjeta que se olvidó en un repaso (le dijeron «De nuevo»): recorre el
  /// paso de reaprendizaje (10 min) antes de volver a la cola de días.
  relearning,

  /// Ya se repasa en días: lo que SM-2 siempre fue. Es la etapa de TODA tarjeta
  /// que ya estaba programada antes de F31.
  review,
}
