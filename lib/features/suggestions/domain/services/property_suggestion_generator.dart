import 'package:sinapsis/core/domain/entities/knowledge_item.dart';

/// Genera y persiste sugerencias de propiedades para un elemento recién
/// procesado, vía [PropertySuggestionService] y [SuggestionRepository].
///
/// Implementada en `data/` (`GeneratePropertySuggestionsUseCase`), no acá:
/// armar el vocabulario que ve el modelo necesita leer `PropertyDefinitions`/
/// `PropertyValues`/`PropertyAliases` directo, una lectura demasiado
/// específica de esta sub-fase como para agregarle un método nuevo a
/// `OrganizeRepository` solo para esto.
// ignore: one_member_abstracts
abstract interface class PropertySuggestionGenerator {
  /// Nunca lanza: cualquier error se traga —degrada a "no se generó
  /// nada"—, mismo criterio que el resto de las integraciones con el
  /// modelo de lenguaje.
  Future<void> generate(KnowledgeItem item);
}
