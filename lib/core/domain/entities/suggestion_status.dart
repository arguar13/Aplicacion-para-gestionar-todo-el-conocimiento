/// En qué punto de revisión está una [Suggestion].
enum SuggestionStatus {
  /// Todavía sin revisar. El estado inicial de toda sugerencia nueva.
  pending,

  /// El usuario la confirmó, y ya se aplicó de verdad.
  accepted,

  /// El usuario la descartó. No se aplicó nada.
  rejected,
}
