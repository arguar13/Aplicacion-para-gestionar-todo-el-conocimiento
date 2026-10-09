import 'package:sinapsis/features/flashcards/domain/services/cloze.dart';
import 'package:sinapsis/features/flashcards/domain/services/flashcard_generator.dart';

/// Propone frases con huecos para completar a partir del contenido de un
/// elemento, con el mismo modelo de lenguaje del chat (F31).
///
/// Como [FlashcardGenerator], nunca guarda nada: solo sugiere, y la persona
/// revisa cada frase antes de que exista una tarjeta. El pedido y la lectura
/// de la respuesta son puros y ya están en `cloze.dart` (`buildClozeRequest`,
/// `parseClozeDrafts`); esto es solo la puerta hacia el modelo.
// ignore: one_member_abstracts
abstract interface class ClozeGenerator {
  /// Hasta [count] frases con huecos basadas en [content]. Lista vacía si el
  /// modelo no devolvió nada que sirviera (sin huecos, o con uno roto): no es
  /// un error, es una sugerencia que no sirvió.
  Future<List<ClozeDraft>> generateClozes({
    required String content,
    int count = 5,
  });
}

/// Un [ClozeGenerator] visto como [FlashcardGenerator]: la frase con sus
/// huecos va en `front`, `back` queda vacío (el complemento de una tarjeta de
/// huecos es opcional) y la cita se conserva.
///
/// Así la generación por partes (`generateFlashcardsByParts`), que lee un texto
/// largo tramo por tramo y ancla cada cita a su lugar, sirve sin cambios para
/// los huecos.
class ClozeAsFlashcardGenerator implements FlashcardGenerator {
  const ClozeAsFlashcardGenerator(this._clozes);

  final ClozeGenerator _clozes;

  @override
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  }) async {
    final drafts = await _clozes.generateClozes(content: content, count: count);
    return [
      for (final draft in drafts)
        FlashcardDraft(front: draft.text, back: '', quote: draft.quote),
    ];
  }
}
