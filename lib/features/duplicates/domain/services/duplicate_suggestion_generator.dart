import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Calcula y persiste el `dedupHash`/`simhash` de un elemento recién
/// guardado, y genera una sugerencia de duplicado si encuentra algo
/// parecido — F7, deduplicación.
///
/// Determinístico, sin modelo de IA (D1): a diferencia de
/// `RelationSuggestionGenerator`/`PropertySuggestionGenerator` (F4/F5),
/// corre siempre, sin ningún gate de `ChatModelManager`/
/// `EmbeddingModelManager`. Sirve tanto para fuentes (enganchado en
/// `ProcessItemUseCase`) como para notas (enganchado en
/// `LibraryRepositoryImpl.save()`) — el mismo generador, dos puntos de
/// enganche (D7).
// ignore: one_member_abstracts
abstract interface class DuplicateSuggestionGenerator {
  /// Nunca lanza: cualquier error se traga —degrada a "no se generó
  /// nada"—, mismo criterio que los otros generadores de sugerencias.
  Future<void> generate(KnowledgeItem item);
}
