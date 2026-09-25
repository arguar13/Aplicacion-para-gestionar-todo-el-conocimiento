import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';

/// Cuántos días trae el calendario de constancia: la misma ventana que
/// [weeklyRetention] —ambos salen de la misma consulta acotada a las
/// últimas semanas, así que comparten la duración—.
const kReviewHistoryDays = kReviewHistoryWeeks * 7;

/// Un día por celda, del más viejo al de hoy, cuántos repasos tuvo cada
/// uno —cero incluido—: el calendario de constancia de D8, "como una
/// racha de GitHub pero sin comparar con nadie".
///
/// [reviewedAtTimes] ya viene acotado a la ventana, misma razón que
/// [weeklyRetention]: acá solo se cuenta por día.
List<DailyActivity> dailyActivity(
  List<DateTime> reviewedAtTimes, {
  required DateTime today,
  int days = kReviewHistoryDays,
}) {
  final todayDate = DateTime(today.year, today.month, today.day);
  final counts = <DateTime, int>{
    for (var i = 0; i < days; i++) todayDate.subtract(Duration(days: i)): 0,
  };

  for (final reviewedAt in reviewedAtTimes) {
    final day = DateTime(reviewedAt.year, reviewedAt.month, reviewedAt.day);
    final current = counts[day];
    if (current != null) counts[day] = current + 1;
  }

  return [
    for (var i = days - 1; i >= 0; i--)
      DailyActivity(
        day: todayDate.subtract(Duration(days: i)),
        count: counts[todayDate.subtract(Duration(days: i))]!,
      ),
  ];
}
