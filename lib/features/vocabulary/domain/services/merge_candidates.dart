import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';

/// Los pares de valores de [stats] que quizá sean el mismo, ordenados por
/// uso combinado: primero los que más elementos limpian.
///
/// Solo compara dentro de una misma categoría de texto. Encuentra tres
/// cosas, en este orden de prioridad si un par cumple más de una:
///  * el mismo texto sin distinguir mayúsculas ni acentos;
///  * uno es el otro con más palabras ("Roma" y "Roma antigua") —por palabras
///    enteras: "Arte" no está dentro de "Artesanía"—;
///  * se escriben casi igual, en nombres de al menos 5 letras: hasta 1 error
///    en uno de hasta 7 letras, 2 en uno más largo, contando un cambio de
///    orden de dos letras como uno.
///
/// El costo se contiene sin comparar todo contra todo: para la ortografía,
/// solo se comparan nombres que empiezan con la misma letra y de largo
/// parecido, y antes de calcular nada se descartan los que no comparten casi
/// las mismas letras; para las palabras contenidas, un índice por palabra.
/// Con 2.000 valores tarda una fracción de segundo. El precio del bloque por
/// primera letra: un error JUSTO en la primera letra no se detecta.
///
/// Función pura y de nivel superior: se puede correr en un isolate.
List<MergeCandidate> findMergeCandidates(List<VocabularyValueStat> stats) {
  final byDefinition = <String, List<_Entry>>{};
  // El texto normalizado de cada valor, calculado UNA vez: ordenar sin
  // acentos —"Época" va antes que "Tema"— no puede normalizar en cada
  // comparación.
  final sortKey = <String, String>{};
  for (final stat in stats) {
    if (!stat.isText) continue;
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

/// Igual que [findMergeCandidates], fuera del hilo de la interfaz: con
/// muchos valores el cálculo se nota, y no debe congelar la pantalla.
Future<List<MergeCandidate>> findMergeCandidatesOffMainThread(
  List<VocabularyValueStat> stats,
) => compute(findMergeCandidates, stats);

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

  void add(_Entry a, _Entry b, MergeCandidateReason reason) {
    final key = a.stat.id.compareTo(b.stat.id) < 0
        ? '${a.stat.id}|${b.stat.id}'
        : '${b.stat.id}|${a.stat.id}';
    if (!seen.add(key)) return;
    out.add(MergeCandidate(first: a.stat, second: b.stat, reason: reason));
  }

  // 1. El mismo texto, distinta grafía.
  final byText = <String, List<_Entry>>{};
  for (final entry in entries) {
    byText.putIfAbsent(entry.normalized, () => []).add(entry);
  }
  for (final group in byText.values) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        add(group[i], group[j], MergeCandidateReason.sameText);
      }
    }
  }

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
    block.sort((a, b) => a.normalized.length.compareTo(b.normalized.length));
    for (var i = 0; i < block.length; i++) {
      final a = block[i];
      for (var j = i + 1; j < block.length; j++) {
        final b = block[j];
        final lengthGap = b.normalized.length - a.normalized.length;
        // Ordenado por largo: pasado 2 de diferencia, ninguno de los que
        // siguen puede parecerse.
        if (lengthGap > 2) break;
        if (a.normalized == b.normalized) continue;
        final allowed = b.normalized.length <= 7 ? 1 : 2;
        if (lengthGap > allowed) continue;
        if (_letterGap(a.letters, b.letters) > allowed * 2) continue;
        if (_withinDistance(a.normalized, b.normalized, allowed)) {
          add(a, b, MergeCandidateReason.similarSpelling);
        }
      }
    }
  }
}

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

/// La diferencia de letras entre dos firmas. Cada edición cambia la firma en
/// a lo sumo 2 unidades, así que más que `2 * errores permitidos` descarta
/// el par sin calcular la distancia.
int _letterGap(List<int> a, List<int> b) {
  var gap = 0;
  for (var i = 0; i < a.length; i++) {
    gap += (a[i] - b[i]).abs();
  }
  return gap;
}

/// Si la distancia de edición entre [a] y [b] es como mucho [max], contando
/// como una sola edición el cambio de orden de dos letras seguidas
/// (distancia de Damerau-Levenshtein restringida).
bool _withinDistance(String a, String b, int max) {
  final n = a.length;
  final m = b.length;
  if ((n - m).abs() > max) return false;

  var previous2 = List<int>.filled(m + 1, 0);
  var previous = List<int>.generate(m + 1, (j) => j);
  for (var i = 1; i <= n; i++) {
    final current = List<int>.filled(m + 1, 0)..[0] = i;
    var rowMin = current[0];
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
    previous2 = previous;
    previous = current;
  }
  return previous[m] <= max;
}
