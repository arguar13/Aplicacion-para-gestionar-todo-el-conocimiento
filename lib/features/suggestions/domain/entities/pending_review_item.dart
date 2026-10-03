import 'package:flutter/foundation.dart';

/// Un elemento con sugerencias esperando que alguien las mire (F27): lo que
/// arma «Para revisar» en «Lo que hizo la IA».
///
/// Lleva los ids y no las sugerencias: «Aceptar todo» y «Descartar todo»
/// necesitan solo eso, y lo que se muestra de cada una lo decodifica el
/// repositorio de sugerencias de siempre, elemento por elemento y solo para
/// los que están en pantalla.
@immutable
class PendingReviewItem {
  const PendingReviewItem({
    required this.itemId,
    required this.itemTitle,
    required this.suggestionIds,
    required this.latestAt,
  });

  final String itemId;
  final String itemTitle;

  /// Las sugerencias pendientes del elemento, de la más vieja a la más nueva.
  final List<String> suggestionIds;

  /// Cuándo llegó la más nueva: el orden de la lista.
  final DateTime latestAt;

  int get count => suggestionIds.length;

  @override
  bool operator ==(Object other) =>
      other is PendingReviewItem &&
      other.itemId == itemId &&
      other.itemTitle == itemTitle &&
      listEquals(other.suggestionIds, suggestionIds) &&
      other.latestAt == latestAt;

  @override
  int get hashCode =>
      Object.hash(itemId, itemTitle, Object.hashAll(suggestionIds), latestAt);
}
