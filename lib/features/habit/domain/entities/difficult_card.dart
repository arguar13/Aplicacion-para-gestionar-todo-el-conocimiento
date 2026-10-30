/// Una tarjeta que de verdad cuesta (F17, D8; F43, M16): se la olvidó al
/// menos una vez.
class DifficultCard {
  const DifficultCard({
    required this.flashcardId,
    required this.front,
    required this.total,
    required this.againCount,
    this.back = '',
    this.itemId = '',
    this.lapses = 0,
    this.sourceStart,
    this.sourceEnd,
  });

  final String flashcardId;
  final String front;
  final String back;

  /// El elemento de la tarjeta: de donde salió.
  final String itemId;

  /// Cuántas veces se repasó en total.
  final int total;

  /// Cuántas de esas veces se calificó «De nuevo».
  final int againCount;

  /// Cuántas veces se la olvidó estando ya en repaso (un «De nuevo» sobre un
  /// repaso en días): lo que la ordena.
  final int lapses;

  /// El fragmento de la fuente del que salió, si lo dice.
  final int? sourceStart;
  final int? sourceEnd;

  double get againRatio => total == 0 ? 0 : againCount / total;

  /// Si dice de qué fragmento de su fuente salió.
  bool get hasSourceRange =>
      sourceStart != null && sourceEnd != null && sourceEnd! > sourceStart!;
}
