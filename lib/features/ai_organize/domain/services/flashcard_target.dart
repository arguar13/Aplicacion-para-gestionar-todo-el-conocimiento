import 'dart:math' as math;

import 'package:sinapsis/features/flashcards/domain/services/flashcard_style.dart';

/// Cuántas tarjetas de repaso hace la IA para un texto (F27, decisión D):
/// de [kMinAiFlashcards] —un artículo corto— a [kMaxAiFlashcards] —un libro
/// o un video largo—, una más cada [kWordsPerExtraFlashcard] palabras.
///
/// Con esos números: un artículo de 800 palabras da 3; uno largo de 3000, 5;
/// una hora de video transcripta (~9000 palabras) da 9; desde ~13.500
/// palabras —un capítulo largo, un video de hora y media— ya son 12. Por
/// palabras y no por caracteres: es lo que se parece a «una cada tantas
/// ideas», y no depende de cuánta puntuación o espacio traiga el texto.
///
/// Con [amount] —el «Menos · Estándar · Más» de la hoja de «Tarjetas
/// didácticas», en «Para cada documento» (F43, M18)— se ajusta sobre eso:
/// *Menos* es la mitad (al menos [kMinFewerAiFlashcards]) y *Más*, una vez y
/// media (como mucho [kMaxMoreAiFlashcards]). Así sigue dependiendo del
/// largo: *Más* de un artículo corto no son las de un libro.
int flashcardTargetFor(
  String text, {
  FlashcardAmount amount = FlashcardAmount.standard,
}) {
  final words = _word.allMatches(text).length;
  if (words == 0) return 0;
  final base = (kMinAiFlashcards + words ~/ kWordsPerExtraFlashcard).clamp(
    kMinAiFlashcards,
    kMaxAiFlashcards,
  );
  final half = (base + 1) ~/ 2;
  return switch (amount) {
    FlashcardAmount.standard => base,
    FlashcardAmount.fewer => math.max(kMinFewerAiFlashcards, half),
    FlashcardAmount.more => math.min(kMaxMoreAiFlashcards, base + half),
  };
}

final _word = RegExp(r'\S+');

const kMinAiFlashcards = 3;
const kMaxAiFlashcards = 12;
const kWordsPerExtraFlashcard = 1500;

/// Lo menos que da *Menos* y lo más que da *Más* (F43, M18).
const kMinFewerAiFlashcards = 2;
const kMaxMoreAiFlashcards = 18;
