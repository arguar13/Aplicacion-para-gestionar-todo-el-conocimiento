import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';

/// Un elemento con correcciones esperando que la persona decida (F33,
/// «Revisar con otro modelo»): lo que arma la sección «Revisión» de «Lo que
/// hizo la IA».
///
/// A diferencia de «Para revisar», trae las correcciones enteras: son pocas
/// —las que propuso una revisión pedida— y cada fila necesita el antes y el
/// después para mostrarse.
@immutable
class CorrectionReviewItem {
  const CorrectionReviewItem({
    required this.itemId,
    required this.itemTitle,
    required this.corrections,
  });

  final String itemId;
  final String itemTitle;

  /// Las pendientes del elemento que todavía valen, de la más vieja a la más
  /// nueva.
  final List<CorrectionSuggestion> corrections;

  /// Cuándo llegó la más nueva: el orden de la lista.
  DateTime get latestAt => corrections.last.createdAt;

  @override
  bool operator ==(Object other) =>
      other is CorrectionReviewItem &&
      other.itemId == itemId &&
      other.itemTitle == itemTitle &&
      listEquals(other.corrections, corrections);

  @override
  int get hashCode =>
      Object.hash(itemId, itemTitle, Object.hashAll(corrections));
}
