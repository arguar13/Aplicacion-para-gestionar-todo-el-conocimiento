import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';

/// Propone preguntas de opción múltiple, con su respuesta correcta, a partir
/// del contenido de un elemento, usando el mismo modelo de lenguaje del chat
/// (F20).
///
/// Reusa [FlashcardDraft]: una pregunta con su respuesta correcta es la
/// misma forma que una tarjeta de repaso libre —`front`/`back`, con `quote`
/// opcional para anclarla después—, y una segunda clase con los mismos tres
/// campos no agregaría nada.
///
/// Las opciones INCORRECTAS nunca salen de acá: el modelo no inventa
/// distractores —la restricción del encargo es que salgan de material real
/// de la bóveda—, así que esto solo propone la pregunta y la respuesta que
/// sí sale de una fuente. Quien arma la tarjeta completa junta esto con los
/// distractores de otra fuente (F20, decisión C) antes de guardar nada.
///
/// Nunca guarda nada por su cuenta, mismo criterio que `FlashcardGenerator`:
/// una sugerencia mala se descarta con un toque, no hay que deshacer nada
/// guardado.
// ignore: one_member_abstracts
abstract interface class QuizQuestionGenerator {
  /// Hasta [count] preguntas basadas en [content]. Lista vacía si el modelo
  /// no devolvió nada interpretable como pregunta y respuesta —no es un
  /// error, es una sugerencia que no sirvió—.
  Future<List<FlashcardDraft>> generateQuizQuestions({
    required String content,
    int count = 5,
  });
}
