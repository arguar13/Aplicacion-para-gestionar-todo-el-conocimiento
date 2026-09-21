import 'package:sinapsis/core/domain/entities/person_name.dart';

/// Un valor del vocabulario con lo que la pantalla de mantenimiento necesita
/// saber de él para decidir qué hacer: en cuántos elementos está y cuántos
/// alias tiene.
///
/// Solo tipos simples a propósito: los candidatos a fusión se calculan en un
/// isolate (`compute`), y lo que viaja hasta allá tiene que poder enviarse.
/// Por eso el nombre de una persona es un [PersonName], que es un valor de
/// texto y un booleano, y no la fila.
class VocabularyValueStat {
  const VocabularyValueStat({
    required this.id,
    required this.label,
    required this.definitionId,
    required this.definitionName,
    required this.isText,
    required this.usage,
    required this.aliasCount,
    this.parentId,
    this.depth = 0,
    this.person,
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

  /// El valor bajo el que está este, o `null` si es una raíz (F13).
  final String? parentId;

  /// Cuántos padres tiene por encima: 0 para una raíz.
  final int depth;

  /// El nombre de la persona, si el valor es de una categoría de personas
  /// (F15): el apellido y el nombre por separado. Uno que nadie partió todavía
  /// viene entero como apellido, sin adivinar dónde termina.
  final PersonName? person;

  /// Si es una persona: se compara por su nombre y no solo por su texto.
  bool get isPerson => person != null;
}

/// Un alias de un valor: otro texto que se resuelve al mismo valor.
class VocabularyAlias {
  const VocabularyAlias({required this.id, required this.alias});

  final String id;
  final String alias;
}

/// Una categoría con cuántos valores tiene: para encontrar las que quedaron
/// vacías.
class VocabularyCategoryStat {
  const VocabularyCategoryStat({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.valueCount,
    this.isPerson = false,
  });

  final String id;
  final String name;
  final bool isSystem;
  final int valueCount;

  /// Si es la categoría de las personas de una obra (F15): sus valores se
  /// agregan y se editan con un apellido y un nombre.
  final bool isPerson;

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

  /// Dos personas con el mismo apellido cuyo nombre es la forma abreviada o
  /// completa del otro —«García Márquez, G.» y «García Márquez, Gabriel»—.
  nameVariant,
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

/// Un conjunto de valores de la misma categoría conectados por candidatos a
/// fusión: lo que la pantalla muestra en una tarjeta, para fusionar varios en
/// uno con una sola operación.
class MergeCandidateGroup {
  const MergeCandidateGroup({required this.values, required this.pairs});

  /// Los valores del grupo, el más usado primero.
  final List<VocabularyValueStat> values;

  /// Los pares que los conectan, con su razón.
  final List<MergeCandidate> pairs;

  String get definitionName => values.first.definitionName;

  /// Cuánto se usa el grupo junto.
  int get combinedUsage => values.fold(0, (sum, v) => sum + v.usage);

  /// El que conviene conservar: el más usado, y a igual uso el más corto.
  VocabularyValueStat get suggestedKeep => values.first;

  Set<MergeCandidateReason> get reasons => {for (final p in pairs) p.reason};

  /// Los valores que, respecto de [keepId], casi seguro son el mismo: se
  /// escriben igual salvo mayúsculas o acentos, o casi igual. Los que solo
  /// comparten palabras con él ("Guerra" y "Guerra fría") NO entran: pueden
  /// ser cosas distintas, y fusionarlas es decisión de quien mira.
  Set<String> probableDuplicatesOf(String keepId) => {
    for (final pair in pairs)
      if (pair.reason != MergeCandidateReason.contained)
        if (pair.first.id == keepId)
          pair.second.id
        else if (pair.second.id == keepId)
          pair.first.id,
  };
}
