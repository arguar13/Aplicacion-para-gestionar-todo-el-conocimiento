import 'package:meta/meta.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// Un renglón de «Mis tarjetas» (F31, ola 2, decisión 72): la tarjeta con lo
/// que la lista necesita y la tarjeta sola no trae.
@immutable
class CardBrowserRow {
  const CardBrowserRow({
    required this.card,
    required this.itemTitle,
    required this.lapses,
  });

  final Flashcard card;

  /// El título del elemento del que sale.
  final String itemTitle;

  /// Cuántas veces se olvidó: un «De nuevo» contestado sobre un repaso (los
  /// pasos de aprender no cuentan).
  final int lapses;

  @override
  bool operator ==(Object other) =>
      other is CardBrowserRow &&
      other.card == card &&
      other.itemTitle == itemTitle &&
      other.lapses == lapses;

  @override
  int get hashCode => Object.hash(card, itemTitle, lapses);
}
