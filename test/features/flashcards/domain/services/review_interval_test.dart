import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
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

  group('previewIntervals', () {
    Flashcard card({int repetitions = 0, int intervalDays = 0}) => Flashcard(
      id: 'c',
      itemId: 'i',
      front: 'Pregunta',
      back: 'Respuesta',
      dueAt: now,
      createdAt: now,
      repetitions: repetitions,
      intervalDays: intervalDays,
    );

    test('una tarjeta nueva: «De nuevo», «Difícil», «Bien» y «Fácil» vuelven '
        'mañana', () {
      final preview = previewIntervals(card(), now: now);

      for (final grade in ReviewGrade.values) {
        expect(preview[grade], (unit: IntervalUnit.days, count: 1));
      }
    });

    test('con un repaso hecho, lo que se muestra es lo que pasa de verdad', () {
      final c = card(repetitions: 1, intervalDays: 1);
      final preview = previewIntervals(c, now: now);

      // Lo mismo que aplica el repaso: ninguna cuenta aparte.
      for (final grade in ReviewGrade.values) {
        expect(
          preview[grade],
          reviewIntervalOf(scheduleNext(c, grade, now: now).intervalDays),
        );
      }
      // «De nuevo» reinicia; las otras crecen.
      expect(preview[ReviewGrade.again]!.unit, IntervalUnit.days);
      expect(preview[ReviewGrade.good]!.count, 6);
    });

    test('una tarjeta madura se espacia: «Fácil» va más lejos que «Bien»', () {
      final c = card(repetitions: 5, intervalDays: 60);
      final preview = previewIntervals(c, now: now);

      expect(preview[ReviewGrade.again]!.unit, IntervalUnit.days);
      expect(preview[ReviewGrade.easy]!.count, greaterThan(0));
      expect(
        scheduleNext(c, ReviewGrade.easy, now: now).intervalDays,
        greaterThan(scheduleNext(c, ReviewGrade.good, now: now).intervalDays),
      );
    });

    test('no toca la tarjeta', () {
      final c = card(repetitions: 2, intervalDays: 6);

      previewIntervals(c, now: now);

      expect(c.repetitions, 2);
      expect(c.intervalDays, 6);
    });
  });
}
