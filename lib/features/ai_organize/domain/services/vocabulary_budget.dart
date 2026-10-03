import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Cuántos caracteres del vocabulario de la persona entran en el pedido de
/// propiedades al modelo (F27): las líneas «Categoría: valor, valor (alias:
/// …)» que arma [describeVocabularyCategory], todas juntas.
///
/// La ventana de Gemma es de 2048 tokens para todo. A unos 3,5 caracteres
/// por token en español —lo que se midió para las tarjetas
/// (`kFlashcardPartChars`)—, el resto del pedido ocupa:
///
/// - la instrucción de propiedades, ~720 caracteres: ~210 tokens;
/// - el comienzo del elemento (`kPropertyExcerptChars`, 2400): ~690 tokens;
/// - el título y el armado del pedido: ~50 tokens;
/// - la respuesta, una línea «PROPIEDAD: categoría | valor» por categoría:
///   ~250 tokens reservados;
/// - las marcas de turno del modelo: ~20 tokens.
///
/// Son ~1220 tokens: quedan ~830. Un vocabulario no es prosa —nombres
/// propios, palabras sueltas, una coma cada dos o tres—, y cuenta más
/// tokens por carácter: con 2,5 caracteres por token, ~2080 caracteres. Se
/// deja en 2000, con margen. Un vocabulario de miles de valores, que antes
/// iba entero y desbordaba la ventana, ahora va en lo más pertinente.
const kPropertyVocabularyBudgetChars = 2000;

/// Cuántos valores de cada categoría entran antes de repartir el resto por
/// pertinencia: que una categoría enorme —los temas— no deje a las demás sin
/// ninguno.
const kMinValuesPerCategory = 3;

/// Cuánto pesa cada señal en lo pertinente que es un valor para un
/// elemento, en `selectVocabularyForPrompt`:
///
/// - [kMentionWeight]: el elemento lo nombra —el valor o uno de sus alias
///   aparece tal cual en el título o el comienzo—. Es lo más seguro que hay,
///   y va primero siempre.
/// - el parecido de sus vectores (coseno, de 0 a 1 en la práctica), tal
///   cual: el orden entre los que no se nombran.
/// - [kUsageWeight]: cuánto se usa, en escala logarítmica respecto del más
///   usado de la bóveda. Desempata entre parecidos: un valor que la persona
///   usa en cien elementos es más probable que uno que usó una vez.
const kMentionWeight = 2.0;
const kUsageWeight = 0.3;

/// Un valor del vocabulario, candidato a ir en el pedido, con lo que dice qué
/// tan pertinente es para el elemento.
@immutable
class VocabularyValueCandidate {
  const VocabularyValueCandidate({
    required this.label,
    this.aliases = const [],
    this.uses = 0,
    this.similarity,
  });

  final String label;

  /// Los otros nombres del valor.
  final List<String> aliases;

  /// En cuántos elementos está puesto.
  final int uses;

  /// El coseno entre su vector y el del elemento; `null` si todavía no tiene
  /// vector calculado.
  final double? similarity;
}

/// Una categoría de texto del vocabulario con sus valores candidatos.
@immutable
class VocabularyCategoryCandidates {
  const VocabularyCategoryCandidates({
    required this.definitionId,
    required this.name,
    required this.values,
  });

  final String definitionId;
  final String name;
  final List<VocabularyValueCandidate> values;
}

/// La línea con que el modelo ve [category]: su nombre, sus valores y, si
/// hay, sus alias. La usa el modelo para armar el pedido y la usa
/// [selectVocabularyForPrompt] para medir lo que ocupa: una sola forma.
String describeVocabularyCategory(PropertyVocabularyCategory category) {
  final values = category.values.join(', ');
  if (category.aliases.isEmpty) return '${category.name}: $values';

  final aliases = category.aliases.join(', ');
  return '${category.name}: $values (alias: $aliases)';
}

/// La parte del vocabulario que va en el pedido de propiedades de un
/// elemento, dentro de [budgetChars] (ver [kPropertyVocabularyBudgetChars]).
///
/// Cada valor se puntúa por lo que el elemento lo nombra, el parecido de los
/// vectores y el uso ([kMentionWeight], [kUsageWeight]). Entran:
///
/// 1. los nombres de las categorías, de la que tiene el valor más pertinente
///    a la que menos —una categoría sin valores también: el modelo puede
///    proponer uno nuevo bajo ella—;
/// 2. por vueltas, el mejor valor de cada categoría, el segundo, hasta
///    [kMinValuesPerCategory];
/// 3. el resto, del más pertinente al menos, mientras entre: lo que ya no
///    entra se saltea, y lo que sobra lo llena algo más corto.
///
/// Cada valor lleva detrás sus alias, si entran: con ellos el modelo
/// reconoce un sinónimo.
///
/// [mentionedIn] es el texto del elemento que el modelo va a ver —el título
/// y el comienzo—: un valor que aparece ahí tal cual va primero.
List<PropertyVocabularyCategory> selectVocabularyForPrompt(
  List<VocabularyCategoryCandidates> categories, {
  required String mentionedIn,
  int budgetChars = kPropertyVocabularyBudgetChars,
}) {
  final text = ' ${normalizeForDedup(mentionedIn)} ';
  final maxUses = categories
      .expand((c) => c.values)
      .fold(0, (most, v) => math.max(most, v.uses));

  double scoreOf(VocabularyValueCandidate value) {
    bool named(String name) {
      final folded = normalizeForDedup(name);
      return folded.isNotEmpty && text.contains(' $folded ');
    }

    final mentioned = named(value.label) || value.aliases.any(named);
    final usage = maxUses == 0
        ? 0.0
        : math.log(1 + value.uses) / math.log(1 + maxUses);
    return (mentioned ? kMentionWeight : 0) +
        (value.similarity ?? 0) +
        kUsageWeight * usage;
  }

  // Cada categoría con sus valores del más pertinente al menos.
  final ranked = [
    for (final category in categories)
      (
        category: category,
        values: <_Scored>[
          for (final value in category.values)
            (value: value, score: scoreOf(value)),
        ]..sort(_byRelevance),
      ),
  ];
  double best(List<_Scored> values) =>
      values.isEmpty ? double.negativeInfinity : values.first.score;
  ranked.sort((a, b) {
    final byBest = best(b.values).compareTo(best(a.values));
    return byBest != 0 ? byBest : a.category.name.compareTo(b.category.name);
  });

  // Lo que va en el pedido, por categoría, y cuánto ocupa ya.
  final chosen = <String, List<VocabularyValueCandidate>>{};
  final aliasesOf = <String, List<String>>{};
  var used = 0;

  // 1. Los nombres: «Nombre: », y el salto de línea entre categorías.
  final included = <VocabularyCategoryCandidates>[];
  for (final entry in ranked) {
    final cost = entry.category.name.length + 2 + (included.isEmpty ? 0 : 1);
    if (used + cost > budgetChars) continue;
    used += cost;
    included.add(entry.category);
    chosen[entry.category.definitionId] = [];
    aliasesOf[entry.category.definitionId] = [];
  }

  /// Lo que cuesta sumar [value] a la línea de su categoría: la coma que lo
  /// separa del anterior, si hay.
  int valueCost(String definitionId, VocabularyValueCandidate value) =>
      value.label.length + (chosen[definitionId]!.isEmpty ? 0 : 2);

  /// Suma [value] y, detrás, sus alias que entren: un alias va con su
  /// valor —es lo que le deja al modelo reconocer un sinónimo—. El primero de
  /// la línea abre « (alias: » y cierra «)»; los demás llevan su coma.
  bool tryAdd(String definitionId, VocabularyValueCandidate value) {
    final cost = valueCost(definitionId, value);
    if (used + cost > budgetChars) return false;
    used += cost;
    chosen[definitionId]!.add(value);
    final aliases = aliasesOf[definitionId]!;
    for (final alias in value.aliases) {
      final aliasCost = alias.length + (aliases.isEmpty ? 10 : 2);
      if (used + aliasCost > budgetChars) continue;
      used += aliasCost;
      aliases.add(alias);
    }
    return true;
  }

  final rankedIncluded = [
    for (final entry in ranked)
      if (chosen.containsKey(entry.category.definitionId)) entry,
  ];

  // 2. Por vueltas, los primeros de cada una.
  final taken = <VocabularyValueCandidate>{};
  for (var round = 0; round < kMinValuesPerCategory; round++) {
    for (final entry in rankedIncluded) {
      if (round >= entry.values.length) continue;
      final value = entry.values[round].value;
      if (tryAdd(entry.category.definitionId, value)) taken.add(value);
    }
  }

  // 3. El resto, del más pertinente al menos, de cualquier categoría.
  final rest = [
    for (final entry in rankedIncluded)
      for (final scored in entry.values)
        if (!taken.contains(scored.value))
          (definitionId: entry.category.definitionId, scored: scored),
  ]..sort((a, b) => _byRelevance(a.scored, b.scored));
  for (final candidate in rest) {
    if (tryAdd(candidate.definitionId, candidate.scored.value)) {
      taken.add(candidate.scored.value);
    }
  }

  return [
    for (final category in included)
      PropertyVocabularyCategory(
        definitionId: category.definitionId,
        name: category.name,
        values: [
          for (final value in chosen[category.definitionId]!) value.label,
        ],
        aliases: aliasesOf[category.definitionId]!,
      ),
  ];
}

/// Un valor con su puntaje.
typedef _Scored = ({VocabularyValueCandidate value, double score});

/// Del más pertinente al menos; entre iguales, el más usado y después por
/// orden alfabético: el mismo vocabulario da siempre el mismo pedido.
int _byRelevance(_Scored a, _Scored b) {
  final byScore = b.score.compareTo(a.score);
  if (byScore != 0) return byScore;
  final byUses = b.value.uses.compareTo(a.value.uses);
  if (byUses != 0) return byUses;
  return a.value.label.compareTo(b.value.label);
}
