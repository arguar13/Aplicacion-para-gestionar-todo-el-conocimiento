import 'package:flutter/foundation.dart';

/// Cuánto de lo que hizo un modelo sigue siendo de la IA (F33): lo que se
/// puede revisar con otro. Por ahora, las tarjetas de pregunta y respuesta.
@immutable
class AiModelWork {
  const AiModelWork({
    required this.model,
    required this.cards,
    required this.items,
  });

  /// El modelo que lo hizo, como lo guardó su pasada; `null` en las pasadas
  /// que no lo anotaban.
  final String? model;

  /// Cuántas tarjetas, y en cuántos elementos.
  final int cards;
  final int items;

  @override
  bool operator ==(Object other) =>
      other is AiModelWork &&
      other.model == model &&
      other.cards == cards &&
      other.items == items;

  @override
  int get hashCode => Object.hash(model, cards, items);

  @override
  String toString() => 'AiModelWork($model: $cards en $items)';
}

/// Un elemento con algo para revisar (F33): cuántas tarjetas de la IA tiene
/// que el revisor miraría. Con eso se cuenta cuánto va a costar.
@immutable
class AiReviewCandidate {
  const AiReviewCandidate({required this.itemId, required this.cards});

  final String itemId;
  final int cards;

  @override
  bool operator ==(Object other) =>
      other is AiReviewCandidate &&
      other.itemId == itemId &&
      other.cards == cards;

  @override
  int get hashCode => Object.hash(itemId, cards);

  @override
  String toString() => 'AiReviewCandidate($itemId: $cards)';
}

/// Cuántos pedidos al modelo lleva revisar [candidates], de a [perCall]
/// tarjetas por pedido como pide el revisor: la cuenta del costo que se
/// muestra antes de empezar.
int aiReviewRequests(
  Iterable<AiReviewCandidate> candidates, {
  required int perCall,
}) => candidates.fold(0, (sum, c) => sum + (c.cards + perCall - 1) ~/ perCall);
