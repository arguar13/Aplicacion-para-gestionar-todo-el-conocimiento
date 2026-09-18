/// Cuánto avanzó el backfill de embeddings, para que la pantalla dibuje
/// una barra de progreso real en vez de un giro indeterminado.
class EmbeddingBackfillProgress {
  const EmbeddingBackfillProgress({
    required this.processedItems,
    required this.totalItems,
    required this.indexedChunks,
  });

  /// Cuántas fuentes ya se recorrieron, de [totalItems].
  final int processedItems;

  /// Cuántas fuentes con al menos un chunk hay en total.
  final int totalItems;

  /// Cuántos chunks nuevos se indexaron en total hasta ahora —puede ser
  /// menor que [processedItems] mientras corre: correrlo de nuevo tras un
  /// backfill previo revisita las mismas fuentes sin volver a indexar
  /// nada, así que "procesado" y "de verdad indexado" no son lo mismo.
  final int indexedChunks;
}

/// Calcula y persiste los embeddings que falten para cada fuente con
/// chunks ya fragmentados —el trabajo bajo demanda de F5 (D13): a
/// diferencia de chunkear (puro, sin modelo, migración de catch-up), esto
/// necesita el modelo de embeddings descargado, así que no puede correr
/// solo en `onUpgrade`.
///
/// Reusa `ChunkEmbeddingIndexer` tal cual (D7): un ítem que falla se
/// reporta y no corta el resto —mismo criterio que
/// `chunkAndPersistSource` con `MigrationIssues`—, y correrlo dos veces
/// no reindexa nada: `ChunkEmbeddingIndexer.indexItem` ya es idempotente
/// por su cuenta.
// ignore: one_member_abstracts
abstract interface class BackfillEmbeddingsUseCase {
  Stream<EmbeddingBackfillProgress> call();
}
