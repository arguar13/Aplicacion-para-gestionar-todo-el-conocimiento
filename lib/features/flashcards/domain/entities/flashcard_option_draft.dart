/// Lo que hace falta para crear una opción de una tarjeta de opción
/// múltiple (F20), antes de que exista: sin `id` —lo pone el repositorio— ni
/// `flashcardId` —lo pone la tarjeta a la que termina perteneciendo—.
class FlashcardOptionDraft {
  const FlashcardOptionDraft({
    required this.content,
    required this.isCorrect,
    this.sourceCharStart,
    this.sourceCharEnd,
  });

  final String content;
  final bool isCorrect;
  final int? sourceCharStart;
  final int? sourceCharEnd;
}
