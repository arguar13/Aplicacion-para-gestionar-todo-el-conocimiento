import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';

/// La etapa de una tarjeta se DEDUCE de sus campos (F31, decisión 69): así lo
/// que estaba programado antes de F31 tiene etapa sin migrar nada.
void main() {
  final now = DateTime(2026, 10, 8, 10);

  Flashcard card({
    int repetitions = 0,
    int intervalDays = 0,
    DateTime? lastReviewedAt,
    int? learningStep,
    DateTime? buriedUntil,
  }) => Flashcard(
    id: 'c',
    itemId: 'i',
    front: 'P',
    back: 'R',
    dueAt: now,
    createdAt: now,
    repetitions: repetitions,
    intervalDays: intervalDays,
    lastReviewedAt: lastReviewedAt,
    learningStep: learningStep,
    buriedUntil: buriedUntil,
  );

  group('phase', () {
    test('sin nada contestado, sin paso ni intervalo: es nueva', () {
      expect(card().phase, CardPhase.newCard);
    });

    test('con un paso y sin intervalo: se aprende', () {
      expect(card(learningStep: 0).phase, CardPhase.learning);
      expect(
        card(learningStep: 1, lastReviewedAt: now).phase,
        CardPhase.learning,
      );
    });

    test(
      'con un paso y con intervalo: se reaprende (la olvidó en un repaso)',
      () {
        final relearning = card(
          learningStep: 0,
          intervalDays: 1,
          lastReviewedAt: now,
        );

        expect(relearning.phase, CardPhase.relearning);
      },
    );

    test('con repeticiones o intervalo y sin paso: está en repaso', () {
      expect(
        card(repetitions: 3, intervalDays: 15, lastReviewedAt: now).phase,
        CardPhase.review,
      );
      // Sin fecha del último repaso, como la dejan las pruebas y algunos
      // importadores: igual se repasa por días.
      expect(card(repetitions: 2, intervalDays: 6).phase, CardPhase.review);
    });

    test('la de antes de F31 que se olvidó (intervalo 1, repeticiones 0) sigue '
        'en repaso: su fecha no cambia de sentido', () {
      final lapsed = card(intervalDays: 1, lastReviewedAt: now);

      expect(lapsed.phase, CardPhase.review);
    });

    test('una tarjeta contestada una vez que quedó sin intervalo ni paso no '
        'vuelve a ser nueva', () {
      expect(card(lastReviewedAt: now).phase, CardPhase.review);
    });
  });

  group('isBuriedAt', () {
    test('pospuesta hasta una fecha futura: sí; llegada la fecha: no', () {
      final buried = card(buriedUntil: DateTime(2026, 10, 9, 4));

      expect(buried.isBuriedAt(now), isTrue);
      expect(buried.isBuriedAt(DateTime(2026, 10, 9, 4)), isFalse);
      expect(buried.isBuriedAt(DateTime(2026, 10, 9, 5)), isFalse);
    });

    test('sin fecha, no está pospuesta', () {
      expect(card().isBuriedAt(now), isFalse);
    });
  });
}
