import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';

/// Cuántas semanas trae el historial de repasos (F17, D8): decisión propia,
/// porque el encargo no fija una duración —tres meses da una curva con
/// forma sin volverse una consulta cara, mismo espíritu que la constante de
/// gracia por defecto de `streak_calculator.dart`—.
const kReviewHistoryWeeks = 12;

/// Agrupa repasos en tramos fijos de 7 días contados hacia atrás desde
/// [today] —mismo criterio que `hasMonthOfWeeklyConsolidation`, sin
/// semana de calendario—, con una fila por semana aunque no haya tenido
/// ningún repaso: una curva con huecos sería más difícil de leer que una
/// que baja a cero.
///
/// [reviews] ya viene acotado a la ventana por quien lo pide —la consulta
/// SQL trae solo lo de las últimas [weeks] semanas—: acá no hace falta
/// filtrar por fecha, solo asignar cada fila a su tramo.
List<WeeklyRetention> weeklyRetention(
  List<({DateTime reviewedAt, bool retained})> reviews, {
  required DateTime today,
  int weeks = kReviewHistoryWeeks,
}) {
  final todayDate = DateTime(today.year, today.month, today.day);
  final totals = List.filled(weeks, 0);
  final retainedCounts = List.filled(weeks, 0);

  for (final review in reviews) {
    final reviewDate = DateTime(
      review.reviewedAt.year,
      review.reviewedAt.month,
      review.reviewedAt.day,
    );
    final daysAgo = todayDate.difference(reviewDate).inDays;
    if (daysAgo < 0) continue;
    final bucket = daysAgo ~/ 7;
    if (bucket >= weeks) continue;
    totals[bucket]++;
    if (review.retained) retainedCounts[bucket]++;
  }

  return [
    for (var bucket = weeks - 1; bucket >= 0; bucket--)
      WeeklyRetention(
        weekStart: todayDate.subtract(Duration(days: bucket * 7 + 6)),
        total: totals[bucket],
        retained: retainedCounts[bucket],
      ),
  ];
}
