/// Una categoría de vocabulario existente, tal como la ve el modelo: su
/// nombre y los valores/alias ya conocidos bajo ella — nunca una categoría
/// nueva, el modelo solo puede proponer un valor bajo una de estas.
class PropertyVocabularyCategory {
  const PropertyVocabularyCategory({
    required this.definitionId,
    required this.name,
    required this.values,
    required this.aliases,
  });

  final String definitionId;
  final String name;
  final List<String> values;
  final List<String> aliases;
}

/// Una propiedad que el modelo cree que aplica al elemento, todavía sin
/// guardar.
///
/// Mismo criterio que `FlashcardDraft`/`RelationSuggestion`: quien la pidió
/// revisa, descarta o confirma antes de que exista de verdad.
class PropertyDraft {
  const PropertyDraft({
    required this.definitionId,
    required this.definitionName,
    required this.value,
  });

  final String definitionId;
  final String definitionName;
  final String value;
}

/// Propone valores de propiedades para un elemento, usando el mismo modelo
/// de lenguaje del chat.
///
/// Nunca guarda nada por su cuenta: solo sugiere, misma asimetría que
/// justifica ese mismo diseño en `FlashcardGenerator`/`RelationSuggestionService`.
// ignore: one_member_abstracts
abstract interface class PropertySuggestionService {
  /// Hasta una propiedad por cada [categories] que el modelo considere
  /// aplicable al elemento. Lista vacía si no encontró ninguna — no es un
  /// error, es una sugerencia que no sirvió.
  Future<List<PropertyDraft>> suggestProperties({
    required String itemTitle,
    required String itemContent,
    required List<PropertyVocabularyCategory> categories,
  });
}
