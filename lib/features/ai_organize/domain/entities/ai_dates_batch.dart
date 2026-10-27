import 'package:flutter/foundation.dart';

/// Un pedido de «Organizar con IA» en la línea de tiempo (F40) y cómo va: lo
/// que muestra la línea mientras la cola de la IA busca las fechas de varios
/// elementos.
@immutable
class AiDatesBatch {
  const AiDatesBatch({
    required this.total,
    this.done = 0,
    this.created = 0,
    this.currentTitle,
  });

  /// Cuántos elementos entraron en el pedido.
  final int total;

  /// Cuántos ya se miraron, hayan dado fechas o no.
  final int done;

  /// Cuántos hechos fechados quedaron en la línea.
  final int created;

  /// El elemento que se está mirando ahora, si alguno.
  final String? currentTitle;

  bool get finished => done >= total;

  AiDatesBatch copyWith({
    int? total,
    int? done,
    int? created,
    String? Function()? currentTitle,
  }) => AiDatesBatch(
    total: total ?? this.total,
    done: done ?? this.done,
    created: created ?? this.created,
    currentTitle: currentTitle == null ? this.currentTitle : currentTitle(),
  );

  @override
  bool operator ==(Object other) =>
      other is AiDatesBatch &&
      other.total == total &&
      other.done == done &&
      other.created == created &&
      other.currentTitle == currentTitle;

  @override
  int get hashCode => Object.hash(total, done, created, currentTitle);

  @override
  String toString() => 'AiDatesBatch($done/$total, $created fechas)';
}
