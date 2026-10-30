import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/services/embedding_similarity.dart';

/// Dos elementos que hablan de lo mismo (F44, paso 5): el coseno entre los
/// centros de sus vectores.
@immutable
class SimilarPair {
  /// [a] y [b] en cualquier orden: quedan ordenados, así un par es siempre el
  /// mismo.
  factory SimilarPair(String a, String b, double score) => a.compareTo(b) <= 0
      ? SimilarPair._(a, b, score)
      : SimilarPair._(b, a, score);

  const SimilarPair._(this.a, this.b, this.score);

  /// El menor de los dos identificadores.
  final String a;

  /// El mayor.
  final String b;

  /// Cuánto se parecen, de -1 a 1.
  final double score;

  /// La clave de este par: ver [similarPairKey].
  String get key => similarPairKey(a, b);

  @override
  bool operator ==(Object other) =>
      other is SimilarPair &&
      other.a == a &&
      other.b == b &&
      other.score == score;

  @override
  int get hashCode => Object.hash(a, b, score);

  @override
  String toString() => 'SimilarPair($a, $b, $score)';
}

/// La clave de un par de elementos, sin importar el orden: lo que se pasa en
/// `except` para dejar afuera los que ya están vinculados.
String similarPairKey(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a\u0000$b' : '$b\u0000$a';

/// Los pares de [vectors] que más se parecen (F44, paso 5): los que llegan a
/// [minSimilarity], del más parecido al menos, sin los de [except]
/// ([similarPairKey]), con a lo sumo [perItem] pares por elemento y [limit] en
/// total.
///
/// Cada elemento se describe por el centro de sus vectores —los de sus
/// fragmentos o los de los tramos de una nota—, de la dimensión más común: un
/// vector de otro modelo no se mezcla, y un elemento sin ninguno de esa
/// dimensión no entra.
///
/// Compara todos con todos: es cuadrático en los elementos, y por eso quien lo
/// llama lo topea (`kMaxGraphItems`, los documentos a la vista) y lo corre
/// fuera del hilo de la interfaz. El tope por elemento reparte las propuestas:
/// un documento central no se lleva todas. Es determinista: a igual parecido,
/// por los identificadores.
List<SimilarPair> mostSimilarPairs(
  Map<String, List<List<double>>> vectors, {
  required double minSimilarity,
  required int perItem,
  required int limit,
  Set<String> except = const {},
}) {
  if (limit <= 0 || perItem <= 0) return const [];
  final dimensions = <int, int>{};
  for (final list in vectors.values) {
    for (final vector in list) {
      dimensions.update(vector.length, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  if (dimensions.isEmpty) return const [];
  // La dimensión más común; a igual cantidad, la más chica, para que no
  // dependa del orden en que llegaron.
  var dimension = -1;
  for (final MapEntry(key: length, value: count) in dimensions.entries) {
    final best = dimensions[dimension] ?? -1;
    if (count > best || (count == best && length < dimension)) {
      dimension = length;
    }
  }

  final ids = <String>[];
  final centers = <List<double>>[];
  for (final id in [...vectors.keys]..sort()) {
    final own = [
      for (final vector in vectors[id]!)
        if (vector.length == dimension) vector,
    ];
    if (own.isEmpty) continue;
    ids.add(id);
    centers.add(centroid(own));
  }

  final candidates = <SimilarPair>[];
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      if (except.contains(similarPairKey(ids[i], ids[j]))) continue;
      final score = cosineSimilarity(centers[i], centers[j]);
      if (score >= minSimilarity) {
        candidates.add(SimilarPair(ids[i], ids[j], score));
      }
    }
  }
  candidates.sort((x, y) {
    final byScore = y.score.compareTo(x.score);
    if (byScore != 0) return byScore;
    final byA = x.a.compareTo(y.a);
    return byA != 0 ? byA : x.b.compareTo(y.b);
  });

  final taken = <String, int>{};
  final pairs = <SimilarPair>[];
  for (final pair in candidates) {
    if (pairs.length >= limit) break;
    if ((taken[pair.a] ?? 0) >= perItem || (taken[pair.b] ?? 0) >= perItem) {
      continue;
    }
    pairs.add(pair);
    taken
      ..update(pair.a, (n) => n + 1, ifAbsent: () => 1)
      ..update(pair.b, (n) => n + 1, ifAbsent: () => 1);
  }
  return pairs;
}
