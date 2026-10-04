import 'package:flutter/foundation.dart';

/// Un pedido de «Crear tarjetas con IA» (F30) y cómo va: lo que muestra
/// Repasar mientras la cola de la IA hace las tarjetas de varios elementos.
@immutable
class AiFlashcardsBatch {
  const AiFlashcardsBatch({
    required this.total,
    this.done = 0,
    this.created = 0,
    this.forReview = 0,
    this.paused = false,
    this.currentTitle,
  });

  /// Cuántos elementos entraron en el pedido.
  final int total;

  /// Cuántos ya se miraron, hayan dado tarjetas o no.
  final int done;

  /// Cuántas tarjetas entraron al repaso.
  final int created;

  /// Cuántas quedaron en «Para revisar» porque su cita no se ubicó.
  final int forReview;

  /// Si la persona lo pausó: lo que estaba en curso termina, y no se toma
  /// otro hasta reanudar.
  final bool paused;

  /// El elemento que se está mirando ahora, si alguno.
  final String? currentTitle;

  bool get finished => done >= total;

  AiFlashcardsBatch copyWith({
    int? total,
    int? done,
    int? created,
    int? forReview,
    bool? paused,
    String? Function()? currentTitle,
  }) => AiFlashcardsBatch(
    total: total ?? this.total,
    done: done ?? this.done,
    created: created ?? this.created,
    forReview: forReview ?? this.forReview,
    paused: paused ?? this.paused,
    currentTitle: currentTitle == null ? this.currentTitle : currentTitle(),
  );

  @override
  bool operator ==(Object other) =>
      other is AiFlashcardsBatch &&
      other.total == total &&
      other.done == done &&
      other.created == created &&
      other.forReview == forReview &&
      other.paused == paused &&
      other.currentTitle == currentTitle;

  @override
  int get hashCode =>
      Object.hash(total, done, created, forReview, paused, currentTitle);

  @override
  String toString() =>
      'AiFlashcardsBatch($done/$total, $created tarjetas, '
      '$forReview para revisar${paused ? ', en pausa' : ''})';
}
