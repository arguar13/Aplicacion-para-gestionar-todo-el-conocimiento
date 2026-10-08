import 'package:meta/meta.dart';

/// Cuánto hay para estudiar hoy en un recorte (F31, decisión 69): lo que
/// muestra la pantalla de entrada a Repasar y la insignia de la navegación.
///
/// [newCards] y [reviews] ya respetan los límites del día; [learning] no los
/// tiene (una tarjeta que se empezó se termina). Los números «sin límite»
/// están en [newAvailable] y [reviewsAvailable], para poder decir «hay 80
/// nuevas; hoy, 20».
@immutable
class StudyCounts {
  const StudyCounts({
    required this.newCards,
    required this.learning,
    required this.reviews,
    required this.newAvailable,
    required this.reviewsAvailable,
    required this.newDoneToday,
    required this.reviewsDoneToday,
    this.nextLearningDue,
  });

  const StudyCounts.empty()
    : newCards = 0,
      learning = 0,
      reviews = 0,
      newAvailable = 0,
      reviewsAvailable = 0,
      newDoneToday = 0,
      reviewsDoneToday = 0,
      nextLearningDue = null;

  /// Tarjetas nuevas que entran hoy (con el límite aplicado).
  final int newCards;

  /// Tarjetas que se están aprendiendo o reaprendiendo y vuelven hoy, en
  /// minutos. Sin límite.
  final int learning;

  /// Repasos que entran hoy (con el límite aplicado).
  final int reviews;

  /// Cuántas nuevas hay en total, sin mirar el límite.
  final int newAvailable;

  /// Cuántos repasos vencen en total, sin mirar el límite.
  final int reviewsAvailable;

  /// Cuántas nuevas y cuántos repasos se hicieron ya hoy, en TODA la bóveda
  /// (los límites son globales, no por recorte).
  final int newDoneToday;
  final int reviewsDoneToday;

  /// Cuándo vuelve la primera tarjeta en aprendizaje (la de fecha más
  /// próxima), o `null` si no hay ninguna que vuelva hoy.
  final DateTime? nextLearningDue;

  /// Lo que hay para estudiar hoy: el número de la insignia.
  int get total => newCards + learning + reviews;

  /// Si no hay nada para estudiar hoy.
  bool get isEmpty => total == 0;

  /// Nuevas que quedan fuera hoy por el límite.
  int get newBeyondLimit => newAvailable - newCards;

  /// Repasos que quedan fuera hoy por el límite.
  int get reviewsBeyondLimit => reviewsAvailable - reviews;

  @override
  bool operator ==(Object other) =>
      other is StudyCounts &&
      other.newCards == newCards &&
      other.learning == learning &&
      other.reviews == reviews &&
      other.newAvailable == newAvailable &&
      other.reviewsAvailable == reviewsAvailable &&
      other.newDoneToday == newDoneToday &&
      other.reviewsDoneToday == reviewsDoneToday &&
      other.nextLearningDue == nextLearningDue;

  @override
  int get hashCode => Object.hash(
    newCards,
    learning,
    reviews,
    newAvailable,
    reviewsAvailable,
    newDoneToday,
    reviewsDoneToday,
    nextLearningDue,
  );

  @override
  String toString() =>
      'StudyCounts(nuevas: $newCards/$newAvailable, aprendiendo: $learning, '
      'repasos: $reviews/$reviewsAvailable)';
}
