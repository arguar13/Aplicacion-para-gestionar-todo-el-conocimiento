import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_activity.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';

/// `weeklyRetention` (F17, D8; F43, M16): pura. Hoy es siempre el viernes
/// 25 de septiembre de 2026 a las 14:00.
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

  test('sin repasos, las doce semanas aparecen igual, todas en cero', () {
    final weeks = weeklyRetention(const [], now: now);

    expect(weeks, hasLength(12));
    expect(weeks.every((w) => w.total == 0 && w.ratio == 0), isTrue);
    // La de hoy va del 19 a las 4:00 hasta hoy; la más vieja, 77 días antes.
    expect(weeks.last.weekStart, DateTime(2026, 9, 19, 4));
    expect(weeks.first.weekStart, DateTime(2026, 7, 4, 4));
  });

  test('«Difícil» se recordó; «De nuevo», no', () {
    final weeks = weeklyRetention([
      at(now, grade: ReviewGrade.hard, count: 3),
      at(now, grade: ReviewGrade.again),
    ], now: now);
    expect(weeks.last.total, 4);
    expect(weeks.last.retained, 3);
  });

  test('solo cuentan los repasos en días, jóvenes o maduros', () {
    final weeks = weeklyRetention([
      at(now, stage: ReviewLogStage.mature),
      at(now, stage: ReviewLogStage.newCard, grade: ReviewGrade.again),
      at(now, stage: ReviewLogStage.learning),
      at(now, stage: ReviewLogStage.relearning),
    ], now: now);
    expect(weeks.last.total, 1);
  });

  test('a las 3:59 todavía es el día de antes', () {
    final weeks = weeklyRetention([
      at(DateTime(2026, 9, 19, 3, 59)),
      at(DateTime(2026, 9, 19, 4)),
    ], now: now);
    expect(weeks.last.total, 1);
    expect(weeks[10].total, 1);
  });

  test('más viejo que la ventana, o en el futuro, no cuenta', () {
    final weeks = weeklyRetention([
      at(DateTime(2026, 7, 4, 3)),
      at(DateTime(2026, 9, 26, 5)),
    ], now: now);
    expect(weeks.every((w) => w.total == 0), isTrue);
  });
}
