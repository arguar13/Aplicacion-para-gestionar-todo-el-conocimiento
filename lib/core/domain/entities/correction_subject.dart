/// Qué corrige una sugerencia de corrección (F33, «Revisar con otro modelo»):
/// algo que hizo la IA y que sigue siendo suyo.
///
/// La columna `suggestions.kind` dice que es una corrección; esto, sobre qué.
/// Va en el `payload_json`, así que sumar uno no cambia el esquema.
enum CorrectionSubject {
  /// Una tarjeta de repaso que hizo la IA: su pregunta y su respuesta.
  flashcard,

  /// Un vínculo que hizo la IA: su tipo y la frase que dice por qué. Solo los
  /// que son una opinión sobre dos elementos, no la estructura —una extracción
  /// o un índice—.
  relation,
}

/// Los datos de una tarjeta en el antes y el después de una corrección.
abstract final class FlashcardCorrectionField {
  static const front = 'front';
  static const back = 'back';
}

/// Los datos de un vínculo en el antes y el después de una corrección: el tipo
/// (`RelationKind.name`) y la frase, vacía si no tiene.
abstract final class RelationCorrectionField {
  static const kind = 'kind';
  static const note = 'note';
}
