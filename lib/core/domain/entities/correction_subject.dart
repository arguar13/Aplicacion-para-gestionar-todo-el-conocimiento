/// Qué corrige una sugerencia de corrección (F33, «Revisar con otro modelo»):
/// algo que hizo la IA y que sigue siendo suyo.
///
/// La columna `suggestions.kind` dice que es una corrección; esto, sobre qué.
/// Va en el `payload_json`, así que sumar uno no cambia el esquema.
enum CorrectionSubject {
  /// Una tarjeta de repaso que hizo la IA: su pregunta y su respuesta.
  flashcard,
}

/// Los datos de una tarjeta en el antes y el después de una corrección.
abstract final class FlashcardCorrectionField {
  static const front = 'front';
  static const back = 'back';
}
