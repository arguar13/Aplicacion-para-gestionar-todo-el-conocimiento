import 'package:flutter/foundation.dart';

/// Cuánto de lo que hizo un modelo sigue siendo de la IA (F33): lo que se
/// puede revisar con otro. Cuenta todo lo que se revisa: las tarjetas de
/// pregunta y respuesta y lo demás (los vínculos, las etiquetas, el tema, los
/// datos de la referencia, la introducción de una nota mapa).
@immutable
class AiModelWork {
  const AiModelWork({
    required this.model,
    required this.things,
    required this.items,
  });

  /// El modelo que lo hizo, como lo guardó su pasada; `null` en las pasadas
  /// que no lo anotaban.
  final String? model;

  /// Cuántas cosas, y en cuántos elementos.
  final int things;
  final int items;

  @override
  bool operator ==(Object other) =>
      other is AiModelWork &&
      other.model == model &&
      other.things == things &&
      other.items == items;

  @override
  int get hashCode => Object.hash(model, things, items);

  @override
  String toString() => 'AiModelWork($model: $things en $items)';
}

/// Un elemento con algo para revisar (F33): cuántas tarjetas de la IA y
/// cuántas cosas más miraría el revisor. Con eso se cuenta cuánto va a
/// costar: las tarjetas y lo demás van en pedidos distintos.
@immutable
class AiReviewCandidate {
  const AiReviewCandidate({
    required this.itemId,
    this.cards = 0,
    this.others = 0,
  });

  final String itemId;
  final int cards;
  final int others;

  /// Las tarjetas y lo demás, sumados.
  int get things => cards + others;

  @override
  bool operator ==(Object other) =>
      other is AiReviewCandidate &&
      other.itemId == itemId &&
      other.cards == cards &&
      other.others == others;

  @override
  int get hashCode => Object.hash(itemId, cards, others);

  @override
  String toString() => 'AiReviewCandidate($itemId: $cards + $others)';
}

/// Cuántos pedidos al modelo lleva revisar [candidates], de a [perCall] cosas
/// por pedido como pide el revisor —las tarjetas por un lado y lo demás por
/// otro, como los mandan sus pasos—: la cuenta del costo que se muestra antes
/// de empezar.
int aiReviewRequests(
  Iterable<AiReviewCandidate> candidates, {
  required int perCall,
}) => candidates.fold(
  0,
  (sum, c) =>
      sum +
      (c.cards + perCall - 1) ~/ perCall +
      (c.others + perCall - 1) ~/ perCall,
);
