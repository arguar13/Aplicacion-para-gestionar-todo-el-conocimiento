/// Cuántas preguntas de una sesión de quiz se fallaron sobre un mismo tema
/// del Atlas (F20), con acceso directo a su nota viva si tiene una.
class TopicErrorSummary {
  const TopicErrorSummary({
    required this.topicLabel,
    required this.missedCount,
    this.livingNoteItemId,
  });

  final String topicLabel;
  final int missedCount;

  /// El elemento de la nota viva etiquetada con este tema, si hay una. Con
  /// más de una, la que tenga el `rowid` menor —mismo criterio que
  /// `AnkiTopicResolver` usa para "el primer tema" de un elemento—; sin
  /// ninguna, `null`: no toda rama del Atlas tiene una nota viva propia
  /// todavía.
  final String? livingNoteItemId;
}
