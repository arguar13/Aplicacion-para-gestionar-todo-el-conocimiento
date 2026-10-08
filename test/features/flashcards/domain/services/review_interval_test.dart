import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/learning_steps.dart';
import 'package:sinapsis/features/flashcards/domain/services/review_interval.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';

void main() {
  final now = DateTime(2026, 10, 8, 12);

  ReviewInterval of(int days) => reviewIntervalOf(days);

  group('reviewIntervalOf', () {
    test('menos de una semana, en días; nunca «0 d»', () {
      expect(of(1), (unit: IntervalUnit.days, count: 1));
      expect(of(6), (unit: IntervalUnit.days, count: 6));
      expect(of(0), (unit: IntervalUnit.days, count: 1));
    });

    test('de una semana a un mes, en semanas', () {
      expect(of(7), (unit: IntervalUnit.weeks, count: 1));
      expect(of(14), (unit: IntervalUnit.weeks, count: 2));
      expect(of(29), (unit: IntervalUnit.weeks, count: 4));
    });

    test('de un mes a un año, en meses', () {
      expect(of(30), (unit: IntervalUnit.months, count: 1));
      expect(of(95), (unit: IntervalUnit.months, count: 3));
      expect(of(364), (unit: IntervalUnit.months, count: 12));
    });

    test('un año o más, en años', () {
      expect(of(365), (unit: IntervalUnit.years, count: 1));
      expect(of(800), (unit: IntervalUnit.years, count: 2));
    });
  });

  group('reviewDelayOf (F31)', () {
    test('menos de una hora, en minutos; nunca «0 min»', () {
      expect(reviewDelayOf(const Duration(minutes: 1)), (
        unit: IntervalUnit.minutes,
        count: 1,
      ));
      expect(reviewDelayOf(const Duration(minutes: 10)), (
        unit: IntervalUnit.minutes,
        count: 10,
      ));
      expect(reviewDelayOf(const Duration(minutes: 7, seconds: 30)), (
        unit: IntervalUnit.minutes,
        count: 8,
      ));
      expect(reviewDelayOf(const Duration(seconds: 20)), (
        unit: IntervalUnit.minutes,
        count: 1,
      ));
      expect(reviewDelayOf(Duration.zero), (
        unit: IntervalUnit.minutes,
        count: 1,
      ));
    });

    test('de una hora a un día, en horas', () {
      expect(reviewDelayOf(const Duration(minutes: 60)), (
        unit: IntervalUnit.hours,
        count: 1,
      ));
      expect(reviewDelayOf(const Duration(hours: 5)), (
        unit: IntervalUnit.hours,
        count: 5,
      ));
    });

    test('de un día en adelante, en la unidad de días, semanas, meses…', () {
      expect(reviewDelayOf(const Duration(days: 1)), (
        unit: IntervalUnit.days,
        count: 1,
      ));
      expect(reviewDelayOf(const Duration(days: 6)), (
        unit: IntervalUnit.days,
        count: 6,
      ));
      expect(reviewDelayOf(const Duration(days: 14)), (
        unit: IntervalUnit.weeks,
        count: 2,
      ));
      expect(reviewDelayOf(const Duration(days: 400)), (
        unit: IntervalUnit.years,
        count: 1,
      ));
    });
  });

  group('previewIntervals', () {
    Flashcard card({
      int repetitions = 0,
      int intervalDays = 0,
      int? learningStep,
      DateTime? lastReviewedAt,
    }) => Flashcard(
      id: 'c',
      itemId: 'i',
      front: 'Pregunta',
      back: 'Respuesta',
      dueAt: now,
      createdAt: now,
      repetitions: repetitions,
      intervalDays: intervalDays,
      learningStep: learningStep,
      lastReviewedAt: lastReviewedAt,
    );

    ReviewInterval min(int n) => (unit: IntervalUnit.minutes, count: n);
    ReviewInterval day(int n) => (unit: IntervalUnit.days, count: n);

    test('una tarjeta nueva: «De nuevo» vuelve en 1 min, «Difícil» en 6 min, '
        '«Bien» en 10 min y «Fácil» en 4 días', () {
      final preview = previewIntervals(card(), now: now);

      expect(preview[ReviewGrade.again], min(1));
      expect(preview[ReviewGrade.hard], min(6));
      expect(preview[ReviewGrade.good], min(10));
      expect(preview[ReviewGrade.easy], day(4));
    });

    test('en el último paso de aprender, «Bien» ya es 1 día', () {
      final preview = previewIntervals(
        card(learningStep: 1, lastReviewedAt: now),
        now: now,
      );

      expect(preview[ReviewGrade.again], min(1));
      expect(preview[ReviewGrade.hard], min(10));
      expect(preview[ReviewGrade.good], day(1));
      expect(preview[ReviewGrade.easy], day(4));
    });

    test('un repaso en días: «De nuevo» son 10 min (se reaprende) y el resto '
        'son días', () {
      final c = card(repetitions: 1, intervalDays: 1, lastReviewedAt: now);
      final preview = previewIntervals(c, now: now);

      expect(preview[ReviewGrade.again], min(10));
      expect(preview[ReviewGrade.good], day(6));
      expect(preview[ReviewGrade.hard], day(6));
    });

    test('una tarjeta que se reaprende: 10 min, 15 min, 1 día y 2 días', () {
      final c = card(intervalDays: 1, learningStep: 0, lastReviewedAt: now);
      final preview = previewIntervals(c, now: now);

      expect(preview[ReviewGrade.again], min(10));
      expect(preview[ReviewGrade.hard], min(15));
      expect(preview[ReviewGrade.good], day(1));
      expect(preview[ReviewGrade.easy], day(2));
    });

    test('lo que se muestra es lo que pasa de verdad, en cada etapa y con cada '
        'respuesta', () {
      final cards = [
        card(),
        card(learningStep: 0, lastReviewedAt: now),
        card(learningStep: 1, lastReviewedAt: now),
        card(repetitions: 1, intervalDays: 1, lastReviewedAt: now),
        card(repetitions: 5, intervalDays: 60, lastReviewedAt: now),
        card(intervalDays: 2, learningStep: 0, lastReviewedAt: now),
        card(intervalDays: 1, lastReviewedAt: now), // la de antes de F31
      ];

      for (final c in cards) {
        final preview = previewIntervals(c, now: now);
        for (final grade in ReviewGrade.values) {
          // Lo que guarda el repaso, aplicado al mismo momento.
          final applied = scheduleNext(c, grade, now: now);
          expect(
            preview[grade],
            reviewDelayOf(applied.dueAt.difference(now)),
            reason: '${c.phase} paso ${c.learningStep} $grade',
          );
        }
      }
    });

    test('respeta los pasos que se le pasen, igual que el repaso', () {
      const steps = LearningSteps(learning: [Duration(minutes: 3)]);

      final preview = previewIntervals(card(), now: now, steps: steps);

      expect(preview[ReviewGrade.again], min(3));
      // Un solo paso: «Bien» ya gradúa.
      expect(preview[ReviewGrade.good], day(1));
    });

    test('una tarjeta madura se espacia: «Fácil» va más lejos que «Bien»', () {
      final c = card(repetitions: 5, intervalDays: 60, lastReviewedAt: now);

      expect(
        scheduleNext(c, ReviewGrade.easy, now: now).intervalDays,
        greaterThan(scheduleNext(c, ReviewGrade.good, now: now).intervalDays),
      );
    });

    test('no toca la tarjeta', () {
      final c = card(repetitions: 2, intervalDays: 6, lastReviewedAt: now);

      previewIntervals(c, now: now);

      expect(c.repetitions, 2);
      expect(c.intervalDays, 6);
      expect(c.learningStep, isNull);
    });
  });
}
