/// Cuántas tarjetas de repaso hace la IA para un texto (F27, decisión D):
/// de [kMinAiFlashcards] —un artículo corto— a [kMaxAiFlashcards] —un libro
/// o un video largo—, una más cada [kWordsPerExtraFlashcard] palabras.
///
/// Con esos números: un artículo de 800 palabras da 3; uno largo de 3000, 5;
/// una hora de video transcripta (~9000 palabras) da 9; desde ~13.500
/// palabras —un capítulo largo, un video de hora y media— ya son 12. Por
/// palabras y no por caracteres: es lo que se parece a «una cada tantas
/// ideas», y no depende de cuánta puntuación o espacio traiga el texto.
int flashcardTargetFor(String text) {
  final words = _word.allMatches(text).length;
  if (words == 0) return 0;
  return (kMinAiFlashcards + words ~/ kWordsPerExtraFlashcard).clamp(
    kMinAiFlashcards,
    kMaxAiFlashcards,
  );
}

final _word = RegExp(r'\S+');

const kMinAiFlashcards = 3;
const kMaxAiFlashcards = 12;
const kWordsPerExtraFlashcard = 1500;
