import 'package:flutter/foundation.dart';

/// Qué tan parecido es un elemento a lo buscado (F30): el coseno de su
/// fragmento o tramo más parecido.
@immutable
class ItemSimilarity {
  const ItemSimilarity({required this.itemId, required this.score});

  final String itemId;
  final double score;

  @override
  bool operator ==(Object other) =>
      other is ItemSimilarity && other.itemId == itemId && other.score == score;

  @override
  int get hashCode => Object.hash(itemId, score);

  @override
  String toString() => 'ItemSimilarity($itemId, $score)';
}

/// Los vectores ya guardados de cada elemento —los de los fragmentos de una
/// fuente y los de los tramos de una nota (F27)—, para buscar por sentido y no
/// solo por palabras (F30, los cuadernos con IA).
///
/// Nunca calcula un vector: lee los que dejó `ChunkEmbeddingIndexer`. Un
/// elemento sin vectores todavía —sin el modelo de vínculos, o sin indexar—
/// simplemente no aparece en [nearestTo], y en [representativeOrder] va
/// después de los que sí tienen.
abstract interface class ItemVectorIndex {
  /// Los elementos vivos cuyo fragmento más parecido a [query] llega a
  /// [minSimilarity], del más parecido al menos, como mucho [limit].
  ///
  /// El más parecido y no el promedio: un libro que habla de Roma en un
  /// capítulo es de Roma aunque el resto sea de otra cosa.
  Future<List<ItemSimilarity>> nearestTo(
    List<double> query, {
    required int limit,
    required double minSimilarity,
  });

  /// [itemIds] en un orden que cubre lo más variado primero: cuando no se
  /// pueden leer todos, los primeros [take] son los que mejor representan el
  /// conjunto —el más central, y después el más distinto de los ya elegidos,
  /// uno por vez—. Sin vectores, el orden de [itemIds] repartido parejo:
  /// primero las puntas y el medio, después lo que queda entre ellos.
  ///
  /// Devuelve los mismos ids, sin perder ni repetir ninguno.
  Future<List<String>> representativeOrder(
    List<String> itemIds, {
    required int take,
  });
}
