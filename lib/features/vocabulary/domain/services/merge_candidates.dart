import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';

/// Los pares de valores de [stats] que quizá sean el mismo, ordenados por
/// uso combinado: primero los que más elementos limpian.
///
/// Solo compara dentro de una misma categoría de texto o de personas. Encuentra
/// tres cosas, en este orden de prioridad si un par cumple más de una:
///  * el mismo texto sin distinguir mayúsculas ni acentos;
///  * uno es el otro con más palabras ("Roma" y "Roma antigua") —por palabras
///    enteras: "Arte" no está dentro de "Artesanía"—;
///  * se escriben casi igual, en nombres de al menos 5 letras: hasta 1 error
///    en uno de hasta 7 letras, 2 en uno más largo, contando un cambio de
///    orden de dos letras como uno.
///
/// Las personas (F15) suman lo que un texto no tiene: el mismo nombre en otro
/// orden —«Gabriel García Márquez» y «García Márquez, Gabriel»— y el mismo
/// apellido con el nombre abreviado —«García Márquez, G.» y «García Márquez,
/// Gabriel»—, que es la razón `nameVariant`.
///
/// El costo se contiene sin comparar todo contra todo: para la ortografía,
/// solo se comparan nombres que empiezan con la misma letra y de largo
/// parecido, y antes de calcular nada se descartan los que no comparten casi
/// las mismas letras; para las palabras contenidas, un índice por palabra.
/// Con 2.000 valores tarda una fracción de segundo. El precio del bloque por
/// primera letra: un error JUSTO en la primera letra no se detecta.
///
/// La salida está ACOTADA por valor: si muchísimos nombres se parecen entre
/// sí ("Guerra aa", "Guerra ab"…), los pares crecerían con el cuadrado —cientos
/// de miles con mil nombres— y ninguna pantalla los necesita. Por eso cada
/// valor se enlaza como mucho con [_maxSpellingPartners] parecidos por
/// ortografía, y un grupo de mismo texto muy grande se enlaza en estrella. Lo
/// que se deja de listar sigue conectado a través de los que sí se listan:
/// `groupMergeCandidates` agrupa igual.
///
/// Función pura y de nivel superior: se puede correr en un isolate.
List<MergeCandidate> findMergeCandidates(List<VocabularyValueStat> stats) {
  final byDefinition = <String, List<_Entry>>{};
  // El texto normalizado de cada valor, calculado UNA vez: ordenar sin
  // acentos —"Época" va antes que "Tema"— no puede normalizar en cada
  // comparación.
  final sortKey = <String, String>{};
  for (final stat in stats) {
    if (!stat.isText && !stat.isPerson) continue;
    final normalized = normalizeVocabularyLabel(stat.label);
    if (normalized.isEmpty) continue;
    sortKey[stat.id] = normalized;
    byDefinition
        .putIfAbsent(stat.definitionId, () => [])
        .add(_Entry(stat, normalized));
  }

  final found = <MergeCandidate>[];
  for (final entries in byDefinition.values) {
    _findInCategory(entries, found);
  }

  found.sort((a, b) {
    final byUsage = b.combinedUsage.compareTo(a.combinedUsage);
    if (byUsage != 0) return byUsage;
    // Un orden total, para que el resultado no dependa del de entrada.
    final byFirst = sortKey[a.first.id]!.compareTo(sortKey[b.first.id]!);
    if (byFirst != 0) return byFirst;
    final bySecond = sortKey[a.second.id]!.compareTo(sortKey[b.second.id]!);
    if (bySecond != 0) return bySecond;
    return a.first.id.compareTo(b.first.id);
  });
  return found;
}

/// Los [candidates] agrupados: cada grupo junta los valores conectados por
/// algún par —"Roma" con "Róma" y "Roma antigua", aunque los dos últimos no
/// se relacionen entre sí—, para poder fusionar varios en uno solo con UNA
/// operación. Ordenados por uso combinado, como los pares.
///
/// Un grupo puede encadenar cosas que no son lo mismo ("Guerra" enlaza con
/// "Guerra fría" y con "Guerra civil"): por eso [MergeCandidateGroup.
/// probableDuplicatesOf] separa lo que casi seguro es un duplicado de lo
/// que solo comparte palabras, y quien lo muestra no debe marcar todo.
List<MergeCandidateGroup> groupMergeCandidates(
  List<MergeCandidate> candidates,
) {
  final parent = <String, String>{};
  String find(String id) {
    var root = id;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    // Compresión de camino: los grupos grandes no se vuelven una cadena.
    var node = id;
    while (parent[node] != root) {
      final next = parent[node]!;
      parent[node] = root;
      node = next;
    }
    return root;
  }

  for (final candidate in candidates) {
    parent
      ..putIfAbsent(candidate.first.id, () => candidate.first.id)
      ..putIfAbsent(candidate.second.id, () => candidate.second.id)
      ..[find(candidate.first.id)] = find(candidate.second.id);
  }

  final valuesByRoot = <String, Map<String, VocabularyValueStat>>{};
  final pairsByRoot = <String, List<MergeCandidate>>{};
  for (final candidate in candidates) {
    final root = find(candidate.first.id);
    (valuesByRoot[root] ??= {})
      ..[candidate.first.id] = candidate.first
      ..[candidate.second.id] = candidate.second;
    (pairsByRoot[root] ??= []).add(candidate);
  }

  final groups = [
    for (final entry in valuesByRoot.entries)
      MergeCandidateGroup(
        values: _mostUsedFirst(entry.value.values.toList()),
        pairs: pairsByRoot[entry.key]!,
      ),
  ];
  final labelKey = {
    for (final g in groups) g: normalizeVocabularyLabel(g.suggestedKeep.label),
  };
  groups.sort((a, b) {
    final byUsage = b.combinedUsage.compareTo(a.combinedUsage);
    if (byUsage != 0) return byUsage;
    final byLabel = labelKey[a]!.compareTo(labelKey[b]!);
    if (byLabel != 0) return byLabel;
    return a.suggestedKeep.id.compareTo(b.suggestedKeep.id);
  });
  return groups;
}

/// El más usado primero; a igual uso, el de nombre más corto, y por último
/// el id: un orden total.
List<VocabularyValueStat> _mostUsedFirst(List<VocabularyValueStat> values) =>
    values..sort((a, b) {
      final byUsage = b.usage.compareTo(a.usage);
      if (byUsage != 0) return byUsage;
      final byLength = a.label.length.compareTo(b.label.length);
      if (byLength != 0) return byLength;
      return a.id.compareTo(b.id);
    });

/// Igual que [findMergeCandidates], fuera del hilo de la interfaz: con
/// muchos valores el cálculo se nota, y no debe congelar la pantalla.
Future<List<MergeCandidate>> findMergeCandidatesOffMainThread(
  List<VocabularyValueStat> stats,
) => compute(findMergeCandidates, stats);

/// Cuántos parecidos por ortografía se listan, como mucho, por valor.
const _maxSpellingPartners = 6;

/// De cuántos valores con el mismo texto se listan todos los pares; más allá,
/// se enlazan en estrella al primero.
const _maxAllPairsGroup = 6;

class _Entry {
  _Entry(this.stat, this.normalized)
    : tokens = normalized.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        ..removeWhere((token) => token.isEmpty),
      letters = _letterCounts(normalized);

  final VocabularyValueStat stat;
  final String normalized;
  final List<String> tokens;

  /// Cuántas veces aparece cada letra (a-z) y cuántos caracteres hay fuera de
  /// a-z: la firma para descartar de un vistazo dos nombres que no se
  /// parecen.
  final List<int> letters;

  /// Con cuántos parecidos por ortografía ya se enlazó: en el propio objeto
  /// y no en un mapa por id, porque se consulta en cada par comparado —
  /// millones de veces en el peor caso— y el hash de una cadena pesaba más
  /// que el resto de la comparación.
  int spellingPartners = 0;
}

/// 26 letras + 1 para todo lo demás.
List<int> _letterCounts(String text) {
  final counts = List<int>.filled(27, 0);
  for (final unit in text.codeUnits) {
    final index = unit - 0x61;
    counts[(index >= 0 && index < 26) ? index : 26]++;
  }
  return counts;
}

final _hasDigit = RegExp(r'\d');

void _findInCategory(List<_Entry> entries, List<MergeCandidate> out) {
  final seen = <String>{};

  bool add(_Entry a, _Entry b, MergeCandidateReason reason) {
    final key = a.stat.id.compareTo(b.stat.id) < 0
        ? '${a.stat.id}|${b.stat.id}'
        : '${b.stat.id}|${a.stat.id}';
    if (!seen.add(key)) return false;
    out.add(MergeCandidate(first: a.stat, second: b.stat, reason: reason));
    return true;
  }

  // 1. El mismo texto, distinta grafía.
  final byText = <String, List<_Entry>>{};
  for (final entry in entries) {
    byText.putIfAbsent(entry.normalized, () => []).add(entry);
  }
  for (final group in byText.values) {
    if (group.length > _maxAllPairsGroup) {
      // Un grupo enorme se enlaza en estrella al de menor id: sigue siendo
      // UN grupo, sin generar todos los pares.
      group.sort((a, b) => a.stat.id.compareTo(b.stat.id));
      for (var j = 1; j < group.length; j++) {
        add(group[0], group[j], MergeCandidateReason.sameText);
      }
      continue;
    }
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        add(group[i], group[j], MergeCandidateReason.sameText);
      }
    }
  }

  // 1b. Las personas, por su nombre: en otro orden o abreviado.
  _findPersonVariants(entries, add);

  // 2. Uno es el otro con más palabras. Un índice por palabra: para cada
  // nombre, solo se miran los que contienen SU primera palabra.
  final byToken = <String, List<_Entry>>{};
  for (final entry in entries) {
    for (final token in entry.tokens.toSet()) {
      byToken.putIfAbsent(token, () => []).add(entry);
    }
  }
  for (final shorter in entries) {
    if (shorter.normalized.length < 3 || shorter.tokens.isEmpty) continue;
    final withFirst = byToken[shorter.tokens.first];
    if (withFirst == null) continue;
    for (final longer in withFirst) {
      if (longer.tokens.length <= shorter.tokens.length) continue;
      if (_containsSequence(longer.tokens, shorter.tokens)) {
        add(shorter, longer, MergeCandidateReason.contained);
      }
    }
  }

  // 3. Se escriben casi igual: por bloques de primera letra, y dentro de
  // cada uno solo nombres de largo parecido.
  final byFirstLetter = <String, List<_Entry>>{};
  for (final entry in entries) {
    // Con menos de 5 letras un solo error ya es un cuarto del nombre:
    // "Roma" y "Rome" no son una errata, son dos nombres.
    if (entry.normalized.length < 5) continue;
    // Un número o un año no es una errata: "Siglo 20" y "Siglo 21" se
    // parecen y son cosas distintas.
    if (_hasDigit.hasMatch(entry.normalized)) continue;
    byFirstLetter.putIfAbsent(entry.normalized[0], () => []).add(entry);
  }
  for (final block in byFirstLetter.values) {
    // Por largo, y a igual largo un orden total: el tope de parecidos por
    // valor se aplica siempre a los mismos, no según cómo llegó la lista.
    block.sort((a, b) {
      final byLength = a.normalized.length.compareTo(b.normalized.length);
      if (byLength != 0) return byLength;
      final byText = a.normalized.compareTo(b.normalized);
      if (byText != 0) return byText;
      return a.stat.id.compareTo(b.stat.id);
    });
    for (var i = 0; i < block.length; i++) {
      final a = block[i];
      if (a.spellingPartners >= _maxSpellingPartners) continue;
      for (var j = i + 1; j < block.length; j++) {
        final b = block[j];
        if (b.spellingPartners >= _maxSpellingPartners) continue;
        final lengthGap = b.normalized.length - a.normalized.length;
        // Ordenado por largo: pasado 2 de diferencia, ninguno de los que
        // siguen puede parecerse.
        if (lengthGap > 2) break;
        if (a.normalized == b.normalized) continue;
        final allowed = b.normalized.length <= 7 ? 1 : 2;
        if (lengthGap > allowed) continue;
        if (!_lettersClose(a.letters, b.letters, allowed * 2)) continue;
        if (_withinDistance(a.normalized, b.normalized, allowed) &&
            add(a, b, MergeCandidateReason.similarSpelling)) {
          a.spellingPartners++;
          b.spellingPartners++;
          if (a.spellingPartners >= _maxSpellingPartners) break;
        }
      }
    }
  }
}

/// Los pares de personas que quizá sean la misma (F15): las que solo difieren
/// en el orden en que se escribió el nombre, y las de un mismo apellido cuyo
/// nombre de pila es la forma abreviada o más corta del otro.
///
/// [add] es el de [_findInCategory]: no repite un par que ya se encontró por
/// otra razón.
void _findPersonVariants(
  List<_Entry> entries,
  bool Function(_Entry, _Entry, MergeCandidateReason) add,
) {
  // El mismo nombre en otro orden: las mismas palabras, ordenadas.
  final byWords = <String, List<_Entry>>{};
  for (final entry in entries) {
    if (!entry.stat.isPerson || entry.tokens.length < 2) continue;
    final key = ([...entry.tokens]..sort()).join(' ');
    byWords.putIfAbsent(key, () => []).add(entry);
  }
  for (final group in byWords.values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.stat.id.compareTo(b.stat.id));
    // Un grupo enorme se enlaza en estrella: sigue siendo UN grupo.
    final star = group.length > _maxAllPairsGroup;
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        if (star && i > 0) break;
        add(group[i], group[j], MergeCandidateReason.sameText);
      }
    }
  }

  // El mismo apellido, con el nombre de pila abreviado o ausente en uno.
  final byFamily = <String, List<_Entry>>{};
  for (final entry in entries) {
    final person = entry.stat.person;
    if (person == null || person.isInstitution) continue;
    final family = normalizeVocabularyLabel(person.family);
    if (family.isEmpty) continue;
    byFamily.putIfAbsent(family, () => []).add(entry);
  }
  for (final group in byFamily.values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.stat.id.compareTo(b.stat.id));

    // Un nombre abreviado que encaja con VARIOS del mismo apellido —«García,
    // J.» con «García, Juan» y con «García, Julia»— es más una pista que una
    // sospecha: se ofrece, pero como «uno contiene al otro», que quien lo mira
    // no da por seguro.
    final partners = <_Entry, int>{};
    final pairs = <(_Entry, _Entry, _GivenRelation)>[];
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final relation = _givenRelation(
          group[i].stat.person!.given,
          group[j].stat.person!.given,
        );
        if (relation == _GivenRelation.none) continue;
        pairs.add((group[i], group[j], relation));
        if (relation == _GivenRelation.initials) {
          // El que se abrevia es el más corto; a igual largo, los dos.
          for (final entry in [group[i], group[j]]) {
            partners[entry] = (partners[entry] ?? 0) + 1;
          }
        }
      }
    }
    for (final (a, b, relation) in pairs) {
      final reason = switch (relation) {
        _GivenRelation.initials =>
          (partners[a]! > 1 || partners[b]! > 1)
              ? MergeCandidateReason.contained
              : MergeCandidateReason.nameVariant,
        _GivenRelation.missing => MergeCandidateReason.contained,
        _GivenRelation.none => throw StateError('unreachable'),
      };
      add(a, b, reason);
    }
  }
}

/// Cómo se relacionan dos nombres de pila del mismo apellido.
enum _GivenRelation {
  /// No se relacionan: son personas distintas.
  none,

  /// Uno es el otro abreviado o más corto: «G.» y «Gabriel».
  initials,

  /// Uno no tiene nombre de pila: «Borges» y «Borges, Jorge Luis».
  missing,
}

_GivenRelation _givenRelation(String a, String b) {
  final first = _givenTokens(a);
  final second = _givenTokens(b);
  if (first.isEmpty && second.isEmpty) return _GivenRelation.none;
  if (first.isEmpty || second.isEmpty) return _GivenRelation.missing;

  final shorter = first.length <= second.length ? first : second;
  final longer = identical(shorter, first) ? second : first;
  var different = first.length != second.length;
  for (var i = 0; i < shorter.length; i++) {
    final s = shorter[i];
    final l = longer[i];
    if (s == l) continue;
    // Solo una inicial se abrevia: «Gabriel» no es una forma de «Gabriela».
    final abbreviates =
        (s.length == 1 && l.startsWith(s)) ||
        (l.length == 1 && s.startsWith(l));
    if (!abbreviates) return _GivenRelation.none;
    different = true;
  }
  return different ? _GivenRelation.initials : _GivenRelation.none;
}

/// Las palabras de un nombre de pila, sin acentos ni puntos: «J.R.R.» son tres.
List<String> _givenTokens(String given) => [
  for (final token in normalizeVocabularyLabel(
    given,
  ).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
    if (token.isNotEmpty) token,
];

/// Si [needle] aparece dentro de [haystack] como palabras consecutivas.
bool _containsSequence(List<String> haystack, List<String> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start++) {
    var matches = true;
    for (var k = 0; k < needle.length; k++) {
      if (haystack[start + k] != needle[k]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

/// Si la diferencia de letras entre dos firmas no pasa de [limit]. Cada
/// edición cambia la firma en a lo sumo 2 unidades, así que más que
/// `2 * errores permitidos` descarta el par sin calcular la distancia. Corta
/// en cuanto se pasa: con nombres que no se parecen, casi nunca hace falta
/// recorrer las 27 posiciones.
bool _lettersClose(List<int> a, List<int> b, int limit) {
  var gap = 0;
  for (var i = 0; i < a.length; i++) {
    gap += (a[i] - b[i]).abs();
    if (gap > limit) return false;
  }
  return true;
}

/// Si la distancia de edición entre [a] y [b] es como mucho [max], contando
/// como una sola edición el cambio de orden de dos letras seguidas
/// (distancia de Damerau-Levenshtein restringida).
bool _withinDistance(String a, String b, int max) {
  final n = a.length;
  final m = b.length;
  if ((n - m).abs() > max) return false;

  // Tres filas reutilizadas, en vez de una lista nueva por cada letra de
  // [a]: con miles de comparaciones, las asignaciones dominaban el costo.
  var previous2 = List<int>.filled(m + 1, 0);
  var previous = List<int>.generate(m + 1, (j) => j);
  var current = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    current[0] = i;
    var rowMin = i;
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = previous[j - 1] + cost;
      if (previous[j] + 1 < value) value = previous[j] + 1;
      if (current[j - 1] + 1 < value) value = current[j - 1] + 1;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          previous2[j - 2] + 1 < value) {
        value = previous2[j - 2] + 1;
      }
      current[j] = value;
      if (value < rowMin) rowMin = value;
    }
    // Ninguna celda de la fila está dentro del límite: no va a estarlo
    // después.
    if (rowMin > max) return false;
    final recycled = previous2;
    previous2 = previous;
    previous = current;
    current = recycled;
  }
  return previous[m] <= max;
}
