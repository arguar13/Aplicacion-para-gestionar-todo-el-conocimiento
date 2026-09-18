import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Genera y persiste sugerencias de vínculo para un elemento recién
/// procesado, orquestando chunking, embeddings, preselección por
/// similitud y el juicio final del LLM en un solo paso secuencial —ver
/// la decisión sobre F5, D8: hay una dependencia de orden estricta entre
/// esos pasos que dos generadores fire-and-forget independientes no
/// podrían garantizar entre sí.
// ignore: one_member_abstracts
abstract interface class RelationSuggestionGenerator {
  /// Nunca lanza: cualquier error se traga —degrada a "no se generó
  /// nada"—, mismo criterio que `PropertySuggestionGenerator` (F4).
  Future<void> generate(KnowledgeItem item);
}
