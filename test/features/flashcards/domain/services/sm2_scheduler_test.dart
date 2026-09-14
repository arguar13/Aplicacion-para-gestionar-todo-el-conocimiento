import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';

void main() {
  final now = DateTime(2026, 9, 13, 10);

  Flashcard newCard({
    double easeFactor = 2.5,
    int intervalDays = 0,
    int repetitions = 0,
  }) => Flashcard(
    id: 'card-1',
    itemId: 'item-1',
    front: '¿Pregunta?',
    back: 'Respuesta',
    dueAt: now,
    createdAt: now,
    easeFactor: easeFactor,
    intervalDays: intervalDays,
    repetitions: repetitions,
  );

  group('progresión de intervalos con "bien"', () {
    test('el primer repaso exitoso queda en 1 día', () {
      final result = scheduleNext(newCard(), ReviewGrade.good, now: now);

      expect(result.repetitions, 1);
      expect(result.intervalDays, 1);
      expect(result.dueAt, now.add(const Duration(days: 1)));
    });

    test('el segundo repaso exitoso salta a 6 días', () {
      final afterFirst = scheduleNext(newCard(), ReviewGrade.good, now: now);

      final result = scheduleNext(afterFirst, ReviewGrade.good, now: now);

      expect(result.repetitions, 2);
      expect(result.intervalDays, 6);
    });

    test('del tercer repaso en adelante, el intervalo anterior se multiplica '
        'por el factor de facilidad', () {
      final afterSecond = newCard(repetitions: 2, intervalDays: 6);

      final result = scheduleNext(afterSecond, ReviewGrade.good, now: now);

      // "Bien" (quality 4) deja el factor de facilidad prácticamente sin
      // cambios (2.5 -> 2.5), así que el intervalo pasa a ser 6 * 2.5 = 15.
      expect(result.repetitions, 3);
      expect(result.intervalDays, 15);
    });
  });

  group('quality < 3 ("de nuevo")', () {
    test('reinicia repeticiones e intervalo, sin importar el historial', () {
      final avanzada = newCard(
        repetitions: 5,
        intervalDays: 60,
        easeFactor: 2.8,
      );

      final result = scheduleNext(avanzada, ReviewGrade.again, now: now);

      expect(result.repetitions, 0);
      expect(result.intervalDays, 1);
      expect(result.dueAt, now.add(const Duration(days: 1)));
    });

    test('baja el factor de facilidad', () {
      final result = scheduleNext(newCard(), ReviewGrade.again, now: now);

      expect(result.easeFactor, lessThan(2.5));
    });
  });

  group('factor de facilidad', () {
    test('nunca baja de 1.3, el piso que define el propio SM-2', () {
      var card = newCard(easeFactor: 1.3);

      // Muchas rachas de "de nuevo" seguidas no deberían poder perforar el
      // piso.
      for (var i = 0; i < 10; i++) {
        card = scheduleNext(card, ReviewGrade.again, now: now);
      }

      expect(card.easeFactor, 1.3);
    });

    test('"fácil" lo sube', () {
      final result = scheduleNext(newCard(), ReviewGrade.easy, now: now);

      expect(result.easeFactor, greaterThan(2.5));
    });

    test('"difícil" lo baja, pero se sigue contando como repaso exitoso', () {
      final result = scheduleNext(newCard(), ReviewGrade.hard, now: now);

      expect(result.easeFactor, lessThan(2.5));
      expect(result.repetitions, 1);
      expect(result.intervalDays, 1);
    });
  });

  test('siempre deja registrado el momento del repaso', () {
    final result = scheduleNext(newCard(), ReviewGrade.good, now: now);

    expect(result.lastReviewedAt, now);
  });
}
