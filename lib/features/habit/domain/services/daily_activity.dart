import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';

/// Cuántos días trae el calendario de constancia (F43, M16): un año, el más
/// largo de los tramos que se eligen («30 días», «3 meses», «1 año»).
const kReviewHistoryDays = 365;

/// Los tramos del calendario de constancia.
enum ActivityRange {
  days30(30),
  months3(90),
  year(kReviewHistoryDays);

  const ActivityRange(this.days);

  final int days;
}

/// Un día de estudio por celda, del más viejo al de hoy, con cuántas
/// respuestas tuvo y cuántas no fueron «De nuevo» —cero incluido—: el
/// calendario de constancia de D8, «como una racha de GitHub pero sin
/// comparar con nadie».
List<DailyActivity> dailyActivity(
  Iterable<ReviewActivityBucket> buckets, {
  required DateTime now,
  int days = kReviewHistoryDays,
  StudyDay day = const StudyDay(),
}) {
  final today = day.startOf(now);
  DateTime dayAt(int back) =>
      DateTime(today.year, today.month, today.day - back, day.startHour);
  final counts = <DateTime, (int, int)>{};
  for (final bucket in buckets) {
    final d = day.startOf(bucket.start);
    final (count, correct) = counts[d] ?? (0, 0);
    counts[d] = (
      count + bucket.count,
      correct + (bucket.passed ? bucket.count : 0),
    );
  }
  return [
    for (var back = days - 1; back >= 0; back--)
      () {
        final d = dayAt(back);
        final (count, correct) = counts[d] ?? (0, 0);
        return DailyActivity(day: d, count: count, correct: correct);
      }(),
  ];
}

/// Las dos rachas del historial (F43, M16), sobre los días de estudio con
/// algún repaso: la actual —hasta hoy, o hasta ayer si hoy todavía no hubo
/// nada: el día no terminó— y la más larga de todas.
///
/// No es la racha de la app (`Streak`), que suma toda la actividad y perdona
/// días: esta cuenta solo repasos del recorte, sin gracia, como en Anki.
({int current, int longest}) studyRuns(
  Iterable<ReviewActivityBucket> buckets, {
  required DateTime now,
  StudyDay day = const StudyDay(),
}) {
  // Cada día como su fecha, para contar de a uno sin depender de las horas.
  DateTime dateOf(DateTime start) {
    final d = day.startOf(start);
    return DateTime.utc(d.year, d.month, d.day);
  }

  final studied = {for (final b in buckets) dateOf(b.start)};
  if (studied.isEmpty) return (current: 0, longest: 0);

  final sorted = studied.toList()..sort();
  var longest = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    run = sorted[i].difference(sorted[i - 1]).inDays == 1 ? run + 1 : 1;
    if (run > longest) longest = run;
  }

  final today = dateOf(now);
  var cursor = studied.contains(today)
      ? today
      : today.subtract(const Duration(days: 1));
  var current = 0;
  while (studied.contains(cursor)) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return (current: current, longest: longest);
}

/// Lo de un tramo del calendario: cuántos días se estudió, de cuántos, y el
/// promedio de respuestas por día estudiado.
({int studied, int days, double average}) activitySummary(
  List<DailyActivity> days,
) {
  final studied = days.where((d) => d.count > 0).toList();
  final answers = studied.fold(0, (sum, d) => sum + d.count);
  return (
    studied: studied.length,
    days: days.length,
    average: studied.isEmpty ? 0 : answers / studied.length,
  );
}
