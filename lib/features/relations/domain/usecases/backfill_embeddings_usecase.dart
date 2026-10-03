/// Cuánto avanzó el backfill de embeddings, para que la pantalla dibuje
/// una barra de progreso real en vez de un giro indeterminado.
class EmbeddingBackfillProgress {
  const EmbeddingBackfillProgress({
    required this.processedItems,
    required this.totalItems,
    required this.indexedChunks,
  });

  /// Cuántos elementos ya se recorrieron, de [totalItems].
  final int processedItems;

  /// Cuántos hay en total: las fuentes con al menos un chunk y las notas
  /// vivas (F27).
  final int totalItems;

  /// Cuántos vectores nuevos se calcularon en total hasta ahora —de los
  /// fragmentos de las fuentes y de los tramos de las notas—; puede ser
  /// menor que [processedItems] mientras corre: correrlo de nuevo tras un
  /// backfill previo revisita las mismas fuentes sin volver a indexar
  /// nada, así que "procesado" y "de verdad indexado" no son lo mismo.
  final int indexedChunks;
}

/// Calcula y persiste los embeddings que falten para cada fuente con
/// chunks ya fragmentados, y para cada nota viva (F27) —el trabajo bajo
/// demanda de F5 (D13): a
/// diferencia de chunkear (puro, sin modelo, migración de catch-up), esto
/// necesita el modelo de embeddings descargado, así que no puede correr
/// solo en `onUpgrade`.
///
/// Reusa `ChunkEmbeddingIndexer` tal cual (D7): un ítem que falla se
/// reporta y no corta el resto —mismo criterio que
/// `chunkAndPersistSource` con `MigrationIssues`—, y correrlo dos veces
/// no reindexa nada: `ChunkEmbeddingIndexer.indexItem` e `indexNote` ya son
/// idempotentes por su cuenta.
// ignore: one_member_abstracts
abstract interface class BackfillEmbeddingsUseCase {
  Stream<EmbeddingBackfillProgress> call();
}
