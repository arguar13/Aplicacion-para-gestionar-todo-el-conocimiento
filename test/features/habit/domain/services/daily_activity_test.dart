import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/true_retention.dart';

/// El calendario de constancia, las rachas y la retención real (F43, M16):
/// puras. Hoy es el viernes 25 de septiembre de 2026 a las 14:00.
void main() {
  final now = DateTime(2026, 9, 25, 14);

  ReviewActivityBucket at(
    DateTime start, {
    ReviewGrade grade = ReviewGrade.good,
    ReviewLogStage stage = ReviewLogStage.young,
    int count = 1,
  }) => ReviewActivityBucket(
    start: start,
    stage: stage,
    grade: grade,
    count: count,
  );

  group('dailyActivity', () {
    test('un año de días de estudio, hoy al final, todos en cero', () {
      final days = dailyActivity(const [], now: now);
      expect(days, hasLength(kReviewHistoryDays));
      expect(days.last.day, DateTime(2026, 9, 25, 4));
      expect(days.first.day, DateTime(2025, 9, 26, 4));
      expect(days.every((d) => d.count == 0 && d.accuracy == null), isTrue);
    });

    test('cada día con sus respuestas y las que no fueron «De nuevo»', () {
      final days = dailyActivity([
        at(DateTime(2026, 9, 25, 9), count: 3),
        at(DateTime(2026, 9, 25, 10), grade: ReviewGrade.again),
        at(DateTime(2026, 9, 25, 3), stage: ReviewLogStage.newCard),
      ], now: now);
      expect((days.last.count, days.last.correct), (4, 3));
      expect(days[days.length - 2].count, 1);
    });
  });

  group('studyRuns', () {
    test('sin repasos, cero', () {
      expect(studyRuns(const [], now: now), (current: 0, longest: 0));
    });

    test('si hoy todavía no, la racha llega hasta ayer', () {
      final runs = studyRuns([
        at(DateTime(2026, 9, 24, 9)),
        at(DateTime(2026, 9, 23, 9)),
        at(DateTime(2026, 9, 20, 9)),
      ], now: now);
      expect(runs, (current: 2, longest: 2));
    });

    test('un día sin repasos antes de ayer la corta', () {
      final runs = studyRuns([
        at(DateTime(2026, 9, 23, 9)),
        for (var d = 1; d <= 5; d++) at(DateTime(2026, 8, d, 9)),
      ], now: now);
      expect(runs, (current: 0, longest: 5));
    });
  });

  test(
    'activitySummary: los días estudiados y el promedio por día estudiado',
    () {
      final summary = activitySummary([
        DailyActivity(day: DateTime(2026, 9, 23, 4), count: 10),
        DailyActivity(day: DateTime(2026, 9, 24, 4), count: 0),
        DailyActivity(day: DateTime(2026, 9, 25, 4), count: 5),
      ]);
      expect(summary, (studied: 2, days: 3, average: 7.5));
    },
  );

  group('trueRetention', () {
    test('ayer no incluye hoy, y la semana son siete días con hoy', () {
      final rows = trueRetention([
        at(DateTime(2026, 9, 25, 9)),
        at(DateTime(2026, 9, 24, 23), grade: ReviewGrade.again),
        at(DateTime(2026, 9, 19, 5), stage: ReviewLogStage.mature),
        at(DateTime(2026, 9, 18, 5), stage: ReviewLogStage.mature),
        // Lo que se está aprendiendo no dice cuánto se retiene.
        at(
          DateTime(2026, 9, 25, 9),
          stage: ReviewLogStage.learning,
          grade: ReviewGrade.again,
        ),
      ], now: now);
      expect(rows[0].young.passed, 1);
      expect(rows[1].young.failed, 1);
      expect(rows[1].young.passed, 0);
      expect(rows[2].total.total, 3);
      expect(rows[3].mature.total, 2);
    });
  });
}
