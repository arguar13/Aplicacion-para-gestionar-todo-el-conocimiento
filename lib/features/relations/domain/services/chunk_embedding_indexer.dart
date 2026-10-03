/// De a cuánto se cortan las notas para calcular sus vectores (F27): unas
/// 500 piezas, holgado dentro de las 1024 que acepta el modelo que se baja
/// (ver `GemmaEmbeddingModelManager`), y del tamaño de un
/// fragmento de fuente, así una nota y una fuente se comparan con vectores
/// que describen trozos parecidos.
const kNoteEmbeddingPieceChars = 2000;

/// Con qué modelo se calcularon los vectores que se guardan: el que baja
/// `GemmaEmbeddingModelManager`. Si el modelo cambia, cambia esto, y los
/// vectores viejos se reconocen por su etiqueta.
const kEmbeddingModelVersion = 'embeddinggemma-300m-seq1024-mixed';

/// Calcula y persiste los embeddings que todavía falten: los de los chunks de
/// una fuente ([indexItem]) y los de los tramos de una nota ([indexNote]).
/// Reusado tanto por la IA que vincula sola (`AutoRelateStep`, F27) como por
/// el backfill bajo demanda (`BackfillEmbeddingsUseCase`) — un solo lugar
/// donde vive cómo se serializa el vector, qué pasa si ya existe, qué
/// `modelVersion` se guarda.
abstract interface class ChunkEmbeddingIndexer {
  /// Cuántos embeddings nuevos escribió para el elemento con este
  /// [itemId] — `0` si ya estaban todos, o si el ítem no tiene ningún
  /// chunk todavía.
  Future<int> indexItem(String itemId);

  /// Deja al día los vectores de la nota [itemId] (`note_embedding`) con su
  /// texto de hoy, cortado en tramos de [kNoteEmbeddingPieceChars]. Solo
  /// calcula los tramos que cambiaron —cada uno se reconoce por el hash de su
  /// texto—: corregir el final de una nota larga no recalcula el principio.
  /// Por tandas, guardando cada una: lo cortado a mitad se retoma.
  ///
  /// Devuelve cuántos vectores calculó; `0` si ya estaban, o si no es una
  /// nota con texto.
  Future<int> indexNote(String itemId);
}
