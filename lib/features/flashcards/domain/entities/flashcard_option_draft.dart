/// Lo que hace falta para crear una opción de una tarjeta de opción
/// múltiple (F20), antes de que exista: sin `id` —lo pone el repositorio— ni
/// `flashcardId` —lo pone la tarjeta a la que termina perteneciendo—.
///
/// [sourceItemId] es de qué elemento sale [sourceCharStart]/[sourceCharEnd];
/// `null` es «el mismo elemento que la tarjeta» —el caso de siempre, una
/// pregunta armada a mano sobre UN elemento—. Un distractor (F20, commit de
/// las fuentes) sale de OTRO elemento por diseño —hermano del Atlas, el otro
/// lado de un `contradicts`, cercano por embedding—, así que necesita decir
/// el suyo propio para que el repositorio busque el chunk en la tabla
/// correcta.
class FlashcardOptionDraft {
  const FlashcardOptionDraft({
    required this.content,
    required this.isCorrect,
    this.sourceItemId,
    this.sourceCharStart,
    this.sourceCharEnd,
  });

  final String content;
  final bool isCorrect;
  final String? sourceItemId;
  final int? sourceCharStart;
  final int? sourceCharEnd;
}
