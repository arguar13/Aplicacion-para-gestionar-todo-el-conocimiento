import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';

/// Cuántas semanas trae la curva de retención (F17, D8): decisión propia,
/// porque el encargo no fija una duración —tres meses da una curva con
/// forma sin volverse ilegible en un teléfono—.
const kReviewHistoryWeeks = 12;

/// La meta de SM-2: recordar nueve de cada diez repasos. Es la línea tenue de
/// la curva (F43, M16).
const kRetentionTarget = 0.9;

/// Agrupa los repasos en tramos de 7 días de estudio contados hacia atrás
/// desde hoy —la semana de hoy termina hoy, sin semana de calendario—, con
/// una fila por semana aunque no haya tenido ningún repaso: una curva con
/// huecos sería más difícil de leer que una que baja a cero.
///
/// Solo cuentan los repasos en días ([ReviewLogStage.isReview]) y se recordó
/// lo que no fue «De nuevo», como en la retención real de Anki: las nuevas y
/// los pasos de minutos no dicen nada de cuánto se retiene.
List<WeeklyRetention> weeklyRetention(
  Iterable<ReviewActivityBucket> buckets, {
  required DateTime now,
  int weeks = kReviewHistoryWeeks,
  StudyDay day = const StudyDay(),
}) {
  final today = day.startOf(now);
  DateTime dayAt(int back) =>
      DateTime(today.year, today.month, today.day - back, day.startHour);
  final oldest = dayAt(weeks * 7 - 1);

  final totals = List.filled(weeks, 0);
  final retained = List.filled(weeks, 0);
  for (final bucket in buckets) {
    if (!bucket.stage.isReview || bucket.start.isBefore(oldest)) continue;
    final back = _daysBetween(day.startOf(bucket.start), today);
    if (back < 0) continue;
    final week = back ~/ 7;
    if (week >= weeks) continue;
    totals[week] += bucket.count;
    if (bucket.passed) retained[week] += bucket.count;
  }

  return [
    for (var week = weeks - 1; week >= 0; week--)
      WeeklyRetention(
        weekStart: dayAt(week * 7 + 6),
        total: totals[week],
        retained: retained[week],
      ),
  ];
}

/// Cuántos días de calendario hay de [from] a [to] —dos principios de día de
/// estudio—, contando fechas y no horas: el día del cambio de horario mide 23
/// o 25.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
