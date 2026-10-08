import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/learning_steps.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';

/// En qué unidad se dice un intervalo corto.
enum IntervalUnit { minutes, hours, days, weeks, months, years }

/// Un intervalo de repaso listo para decirse: «10 min», «3 h», «6 d», «3
/// sem», «2 m», «1 a».
typedef ReviewInterval = ({IntervalUnit unit, int count});

/// Cuánto falta para que vuelva una tarjeta que está a [days] días: en la
/// unidad más grande que lo deja en un número chico, sin decimales.
///
/// Es lo que se muestra bajo cada botón de calificar, como en Anki: antes de
/// contestar, la persona ve qué le cuesta cada respuesta en tiempo.
ReviewInterval reviewIntervalOf(int days) {
  if (days < 7) return (unit: IntervalUnit.days, count: days < 1 ? 1 : days);
  if (days < 30) return (unit: IntervalUnit.weeks, count: (days / 7).round());
  if (days < 365) {
    return (unit: IntervalUnit.months, count: (days / 30).round());
  }
  return (unit: IntervalUnit.years, count: (days / 365).round());
}

/// Lo mismo que [reviewIntervalOf], pero para un tiempo cualquiera (F31): en
/// minutos si es menos de una hora («1 min», «10 min»), en horas si es menos de
/// un día, y de un día en adelante, en la unidad de [reviewIntervalOf].
///
/// Nunca dice «0 min»: lo que vuelve en menos de un minuto se dice como 1.
ReviewInterval reviewDelayOf(Duration delay) {
  final minutes = (delay.inSeconds / 60).round();
  if (minutes < 60) {
    return (unit: IntervalUnit.minutes, count: minutes < 1 ? 1 : minutes);
  }
  final hours = (minutes / 60).round();
  if (hours < 24) return (unit: IntervalUnit.hours, count: hours);
  return reviewIntervalOf((minutes / (24 * 60)).round());
}

/// Lo que pasaría con [card] con cada calificación, sin tocarla: cuándo
/// vuelve si contestás «De nuevo», «Difícil», «Bien» o «Fácil».
///
/// Calcula con el mismo [scheduleNext] que aplica el repaso de verdad, y lo
/// que dice es cuánto falta hasta la fecha que ese cálculo le da a la tarjeta
/// —minutos si vuelve dentro de la sesión, días si no—: lo que se muestra y lo
/// que pasa no pueden ser dos cuentas distintas.
Map<ReviewGrade, ReviewInterval> previewIntervals(
  Flashcard card, {
  required DateTime now,
  LearningSteps steps = LearningSteps.standard,
}) => {
  for (final grade in ReviewGrade.values)
    grade: reviewDelayOf(
      scheduleNext(card, grade, now: now, steps: steps).dueAt.difference(now),
    ),
};
