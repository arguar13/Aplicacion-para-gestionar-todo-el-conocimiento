/// Una tarjeta con una proporción alta de `again` entre sus repasos
/// (F17, D8): la que más cuesta recordar.
class DifficultCard {
  const DifficultCard({
    required this.flashcardId,
    required this.front,
    required this.total,
    required this.againCount,
  });

  final String flashcardId;
  final String front;

  /// Cuántas veces se repasó en total.
  final int total;

  /// Cuántas de esas veces se calificó `again`.
  final int againCount;

  double get againRatio => total == 0 ? 0 : againCount / total;
}
