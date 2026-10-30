import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/services/review_stats_math.dart';

/// Las cuentas de las estadísticas (F43, M17): puras. Hoy es el jueves 8 de
/// octubre de 2026 a las 10:00.
void main() {
  final now = DateTime(2026, 10, 8, 10);

  group('daySeries', () {
    test('30 días: una barra por día, hoy al final, los vacíos en cero', () {
      final bars = daySeries(
        period: StatsPeriod.days30,
        now: now,
        first: null,
        width: 2,
        valuesOf: (day) => day == DateTime(2026, 10, 8, 4) ? [3, 1] : null,
      );
      expect(bars, hasLength(30));
      expect(bars.last.start, DateTime(2026, 10, 8, 4));
      expect(bars.first.start, DateTime(2026, 9, 9, 4));
      expect(bars.last.values, [3, 1]);
      expect(bars.last.total, 4);
      expect(bars.first.total, 0);
    });

    test('«todo» empieza el primer día con algo', () {
      final bars = daySeries(
        period: StatsPeriod.all,
        now: now,
        first: DateTime(2026, 10, 6, 9),
        width: 1,
        valuesOf: (_) => [1],
      );
      expect(bars, hasLength(3));
      expect(bars.every((b) => b.days == 1), isTrue);
    });

    test('más de 90 días van de a semanas que terminan hoy', () {
      final bars = daySeries(
        period: StatsPeriod.all,
        now: now,
        first: DateTime(2026, 1, 1, 12),
        width: 1,
        valuesOf: (_) => [1],
      );
      expect(bars.every((b) => b.days == 7), isTrue);
      expect(bars.last.start, DateTime(2026, 10, 2, 4));
      expect(bars.last.total, 7);
      // Del 1 de enero al 8 de octubre son 281 días: 41 semanas.
      expect(bars, hasLength(41));
    });
  });

  test('buttonsByPeriod: cada período corta en el principio de su día', () {
    ReviewActivityBucket at(DateTime start, ReviewGrade grade) =>
        ReviewActivityBucket(
          start: start,
          stage: ReviewLogStage.relearning,
          grade: grade,
          count: 2,
        );
    final buttons = buttonsByPeriod([
      at(DateTime(2026, 9, 9, 4), ReviewGrade.good),
      at(DateTime(2026, 9, 9, 3, 45), ReviewGrade.again),
      at(DateTime(2025, 1, 1, 9), ReviewGrade.easy),
    ], now: now);
    expect(
      buttons[StatsPeriod.days30]!.of(StatsStage.learning),
      const ButtonUsage(good: 2),
    );
    expect(buttons[StatsPeriod.days90]!.overall.total, 4);
    expect(
      buttons[StatsPeriod.all]!.of(StatsStage.learning),
      const ButtonUsage(again: 2, good: 2, easy: 2),
    );
  });

  test('easeBands: de a veinte puntos desde 130, la última abierta', () {
    final bands = easeBands(const [
      EaseCount(percent: 130, count: 1),
      EaseCount(percent: 149, count: 2),
      EaseCount(percent: 150, count: 3),
      EaseCount(percent: 250, count: 4),
      EaseCount(percent: 400, count: 5),
    ]);
    expect(bands, hasLength(kEaseBands));
    expect(
      (bands.first.from, bands.first.to, bands.first.count),
      (130, 149, 3),
    );
    expect(bands[1].count, 3);
    expect((bands[6].from, bands[6].count), (250, 4));
    expect((bands.last.from, bands.last.to, bands.last.count), (290, null, 5));
  });

  test('IntervalRange.of: los bordes de cada tramo', () {
    expect(
      [
        for (final d in [1, 2, 7, 8, 21, 22, 90, 91]) IntervalRange.of(d),
      ],
      [
        IntervalRange.oneDay,
        IntervalRange.upToWeek,
        IntervalRange.upToWeek,
        IntervalRange.upToThreeWeeks,
        IntervalRange.upToThreeWeeks,
        IntervalRange.upToThreeMonths,
        IntervalRange.upToThreeMonths,
        IntervalRange.longer,
      ],
    );
  });

  test('bestHour: hace falta un mínimo de respuestas', () {
    ReviewStats withHours(List<HourAccuracy> hours) => ReviewStats(
      today: const TodayStats.empty(),
      forecast: const ReviewForecast(days: [], overdue: 0),
      daily: const [],
      distribution: const CardDistribution.empty(),
      buttons: const {},
      intervals: const {},
      ease: const [],
      hours: hours,
      added: const [],
    );
    expect(
      withHours(const [
        HourAccuracy(hour: 8, answers: 9, correct: 9),
        HourAccuracy(hour: 9, answers: 20, correct: 15),
        HourAccuracy(hour: 10, answers: 40, correct: 30),
      ]).bestHour?.hour,
      10,
    );
    expect(
      withHours(const [HourAccuracy(hour: 8, answers: 9, correct: 9)]).bestHour,
      isNull,
    );
  });
}
