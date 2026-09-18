import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Calcula y persiste los embeddings que todavía falten para los chunks de
/// un elemento. Reusado tanto por el hook en vivo
/// (`GenerateRelationSuggestionsUseCase`) como por el backfill bajo
/// demanda (`BackfillEmbeddingsUseCase`) — un solo lugar donde vive cómo
/// se serializa el vector, qué pasa si ya existe, qué `modelVersion` se
/// guarda.
// ignore: one_member_abstracts
abstract interface class ChunkEmbeddingIndexer {
  /// Cuántos embeddings nuevos escribió para el [KnowledgeItem] con este
  /// [itemId] — `0` si ya estaban todos, o si el ítem no tiene ningún
  /// chunk todavía.
  Future<int> indexItem(String itemId);
}
