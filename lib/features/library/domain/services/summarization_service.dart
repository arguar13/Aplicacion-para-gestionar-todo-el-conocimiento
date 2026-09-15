/// Redacta un resumen de un contenido largo.
///
/// Interfaz propia y no un método más de `ChatModel` por el mismo motivo
/// que ya separa `FlashcardGenerator` y `RelationSuggestionService`: quien
/// pide un resumen —el detalle de un elemento, el lector de documentos— no
/// tiene por qué conocer nada de citas ni de conversaciones, solo "dame la
/// versión corta de esto". La implementación real sigue siendo el mismo
/// modelo de Gemma ya cargado (`GemmaChatModel`), no un motor aparte.
// ignore: one_member_abstracts
abstract interface class SummarizationService {
  /// El resumen de [content], en unos pocos párrafos.
  ///
  /// Lanza si el modelo de lenguaje todavía no está descargado — quien
  /// llama ya tiene que haber comprobado `ChatModelManager.isReady()`
  /// antes, mismo contrato que `ChatModel.answer`.
  Future<String> summarize({required String content});
}
