/// Un valor del vocabulario con lo que la pantalla de mantenimiento necesita
/// saber de él para decidir qué hacer: en cuántos elementos está y cuántos
/// alias tiene.
///
/// Solo tipos simples a propósito: los candidatos a fusión se calculan en un
/// isolate (`compute`), y lo que viaja hasta allá tiene que poder enviarse.
class VocabularyValueStat {
  const VocabularyValueStat({
    required this.id,
    required this.label,
    required this.definitionId,
    required this.definitionName,
    required this.isText,
    required this.usage,
    required this.aliasCount,
  });

  final String id;
  final String label;
  final String definitionId;
  final String definitionName;

  /// Si la categoría es de texto. Una de fechas o de números no tiene
  /// candidatos a fusión: "44 a.C." y "45 a.C." se parecen y son distintas.
  final bool isText;

  /// En cuántos elementos está puesto.
  final int usage;
  final int aliasCount;
}

/// Una categoría con cuántos valores tiene: para encontrar las que quedaron
/// vacías.
class VocabularyCategoryStat {
  const VocabularyCategoryStat({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.valueCount,
  });

  final String id;
  final String name;
  final bool isSystem;
  final int valueCount;

  /// Una categoría sin ningún valor que el usuario creó y se puede borrar. Las
  /// de sistema no cuentan: que "Tema" esté vacía es normal, y no se puede
  /// borrar.
  bool get isOrphan => valueCount == 0 && !isSystem;
}

/// Por qué dos valores parecen ser el mismo.
enum MergeCandidateReason {
  /// El mismo texto sin distinguir mayúsculas ni acentos.
  sameText,

  /// Uno es el otro más palabras: "Roma" y "Roma antigua".
  contained,

  /// Se escriben casi igual: una letra de más, de menos o cambiada.
  similarSpelling,
}

/// Dos valores de la misma categoría que quizá sean el mismo.
///
/// Es una sugerencia para que una persona la mire, nunca una fusión hecha:
/// "Roma" y "Roma antigua" pueden ser lo mismo o no.
class MergeCandidate {
  const MergeCandidate({
    required this.first,
    required this.second,
    required this.reason,
  });

  final VocabularyValueStat first;
  final VocabularyValueStat second;
  final MergeCandidateReason reason;

  /// Cuánto se usa el par junto: con lo que se ordenan, para que arriba
  /// queden los que más elementos limpian.
  int get combinedUsage => first.usage + second.usage;

  /// El que conviene conservar al fusionarlos: el más usado, y a igual uso el
  /// de nombre más corto.
  VocabularyValueStat get suggestedKeep {
    if (first.usage != second.usage) {
      return first.usage > second.usage ? first : second;
    }
    return first.label.length <= second.label.length ? first : second;
  }
}
