import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Genera la sugerencia de referencia de un elemento si
/// `extractedMetadataOf` encuentra algo que proponer (F15, D12).
///
/// Nunca lanza: un fallo se traga, mismo criterio que
/// `DuplicateSuggestionGenerator` y el resto de los generadores
/// fire-and-forget de `ProcessItemUseCase`.
// ignore: one_member_abstracts
abstract interface class MetadataSuggestionGenerator {
  Future<void> generate(KnowledgeItem item);
}
