import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';

/// En qué unidad se dice un intervalo corto.
enum IntervalUnit { days, weeks, months, years }

/// Un intervalo de repaso listo para decirse: «6 d», «3 sem», «2 m», «1 a».
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

/// Lo que pasaría con [card] con cada calificación, sin tocarla: cuándo
/// vuelve si contestás «De nuevo», «Difícil», «Bien» o «Fácil».
///
/// Calcula con el mismo [scheduleNext] que aplica el repaso de verdad: lo que
/// se muestra y lo que pasa no pueden ser dos cuentas distintas.
Map<ReviewGrade, ReviewInterval> previewIntervals(
  Flashcard card, {
  required DateTime now,
}) => {
  for (final grade in ReviewGrade.values)
    grade: reviewIntervalOf(scheduleNext(card, grade, now: now).intervalDays),
};
