/// Una tarjeta propuesta por el generador, todavía sin guardar: quien la
/// pidió tiene que poder revisarla, editarla o descartarla antes de que
/// exista de verdad.
class FlashcardDraft {
  const FlashcardDraft({required this.front, required this.back, this.quote});

  final String front;
  final String back;

  /// La frase del contenido de la que dice salir la respuesta, tal como la
  /// escribió el modelo (F11). Es una AFIRMACIÓN del modelo, no un dato:
  /// nadie sabe todavía si esa frase está de verdad en el texto. Quien la use
  /// para señalar un lugar tiene que comprobarlo antes con `locateQuote`.
  final String? quote;
}

/// Propone tarjetas de estudio a partir del contenido de un elemento,
/// usando el mismo modelo de lenguaje del chat.
///
/// Nunca guarda nada por su cuenta: solo sugiere. Una sugerencia mala se
/// descarta con un toque; una tarjeta guardada por error hay que borrarla a
/// mano — la asimetría es real, y es la razón por la que esto no escribe
/// directamente en `FlashcardRepository`.
// ignore: one_member_abstracts
abstract interface class FlashcardGenerator {
  /// Hasta [count] tarjetas basadas en [content]. Lista vacía si el modelo
  /// no devolvió nada que se pudiera interpretar como pregunta y
  /// respuesta — no es un error, es una sugerencia que no sirvió.
  Future<List<FlashcardDraft>> generate({
    required String content,
    int count = 5,
  });
}
