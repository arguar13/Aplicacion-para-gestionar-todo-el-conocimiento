import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/habit/domain/entities/true_retention.dart';

/// La retención real, como la tabla de Anki (F43, M16): de los repasos en
/// días de cada tramo, cuántos se recordaron —todo lo que no fue «De
/// nuevo»—, separados en jóvenes y maduros por el intervalo de antes.
///
/// Las nuevas y los pasos de minutos no cuentan: lo que se está aprendiendo
/// no dice nada de cuánto se retiene.
List<TrueRetentionRow> trueRetention(
  Iterable<ReviewActivityBucket> buckets, {
  required DateTime now,
  StudyDay day = const StudyDay(),
}) {
  final today = day.startOf(now);
  DateTime dayAt(int back) =>
      DateTime(today.year, today.month, today.day - back, day.startHour);

  final tally = {
    for (final period in RetentionPeriod.values)
      period: {
        ReviewLogStage.young: [0, 0],
        ReviewLogStage.mature: [0, 0],
      },
  };
  for (final bucket in buckets) {
    if (!bucket.stage.isReview) continue;
    for (final period in RetentionPeriod.values) {
      final from = dayAt(period.offset + period.days - 1);
      final to = dayAt(period.offset - 1);
      if (bucket.start.isBefore(from) || !bucket.start.isBefore(to)) continue;
      tally[period]![bucket.stage]![bucket.passed ? 0 : 1] += bucket.count;
    }
  }

  PassFail of(List<int> counts) =>
      PassFail(passed: counts[0], failed: counts[1]);
  return [
    for (final period in RetentionPeriod.values)
      TrueRetentionRow(
        period: period,
        young: of(tally[period]![ReviewLogStage.young]!),
        mature: of(tally[period]![ReviewLogStage.mature]!),
      ),
  ];
}
