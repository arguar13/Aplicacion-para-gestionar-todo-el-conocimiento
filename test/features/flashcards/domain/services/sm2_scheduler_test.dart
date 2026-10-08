import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/learning_steps.dart';
import 'package:sinapsis/features/flashcards/domain/services/sm2_scheduler.dart';

/// El calendario de repaso (F31, decisión 69): SM-2 para los repasos en días y
/// pasos de aprendizaje (1 min y 10 min) para lo nuevo y lo olvidado.
void main() {
  final now = DateTime(2026, 9, 13, 10);

  Flashcard card({
    double easeFactor = 2.5,
    int intervalDays = 0,
    int repetitions = 0,
    int? learningStep,
    DateTime? lastReviewedAt,
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
    learningStep: learningStep,
    lastReviewedAt: lastReviewedAt,
  );

  /// Una tarjeta nueva: nunca se contestó.
  Flashcard newCard() => card();

  /// Aprendiéndose, en el paso [step]: ya se contestó al menos una vez.
  Flashcard learning(int step) => card(learningStep: step, lastReviewedAt: now);

  /// Ya se repasa en días.
  Flashcard inReview({
    int repetitions = 3,
    int intervalDays = 15,
    double easeFactor = 2.5,
  }) => card(
    repetitions: repetitions,
    intervalDays: intervalDays,
    easeFactor: easeFactor,
    lastReviewedAt: now,
  );

  /// Se olvidó en un repaso: reaprendiéndose en su único paso.
  Flashcard relearning({int intervalDays = 1, double easeFactor = 1.7}) => card(
    intervalDays: intervalDays,
    easeFactor: easeFactor,
    learningStep: 0,
    lastReviewedAt: now,
  );

  Flashcard next(Flashcard c, ReviewGrade g, {LearningSteps? steps}) =>
      scheduleNext(c, g, now: now, steps: steps ?? LearningSteps.standard);

  Duration delayOf(Flashcard c) => c.dueAt.difference(now);

  group('una tarjeta nueva', () {
    test('«De nuevo» vuelve en 1 minuto, en el paso 0', () {
      final result = next(newCard(), ReviewGrade.again);

      expect(result.learningStep, 0);
      expect(delayOf(result), const Duration(minutes: 1));
      expect(result.phase, CardPhase.learning);
      expect(result.intervalDays, 0);
      expect(result.repetitions, 0);
    });

    test('«Difícil» vuelve en 6 minutos (el promedio de 1 y 10), sin pasar '
        'de paso', () {
      final result = next(newCard(), ReviewGrade.hard);

      expect(result.learningStep, 0);
      expect(delayOf(result), const Duration(minutes: 6));
    });

    test('«Bien» pasa al paso 1: vuelve en 10 minutos', () {
      final result = next(newCard(), ReviewGrade.good);

      expect(result.learningStep, 1);
      expect(delayOf(result), const Duration(minutes: 10));
      expect(result.phase, CardPhase.learning);
    });

    test('«Fácil» se gradúa: sale de los pasos y vuelve en 4 días', () {
      final result = next(newCard(), ReviewGrade.easy);

      expect(result.learningStep, isNull);
      expect(result.intervalDays, 4);
      expect(result.repetitions, 2);
      expect(delayOf(result), const Duration(days: 4));
      expect(result.phase, CardPhase.review);
    });

    test('aprender no toca la facilidad, conteste lo que conteste', () {
      for (final grade in ReviewGrade.values) {
        expect(next(newCard(), grade).easeFactor, 2.5, reason: grade.name);
      }
    });

    test('siempre deja registrado el momento del repaso', () {
      for (final grade in ReviewGrade.values) {
        expect(next(newCard(), grade).lastReviewedAt, now, reason: grade.name);
      }
    });
  });

  group('una tarjeta que se está aprendiendo', () {
    test('en el paso 0 responde igual que una nueva', () {
      for (final grade in ReviewGrade.values) {
        final fromNew = next(newCard(), grade);
        final fromStep0 = next(learning(0), grade);
        expect(fromStep0.learningStep, fromNew.learningStep, reason: '$grade');
        expect(fromStep0.dueAt, fromNew.dueAt, reason: '$grade');
        expect(fromStep0.intervalDays, fromNew.intervalDays, reason: '$grade');
        expect(fromStep0.repetitions, fromNew.repetitions, reason: '$grade');
      }
    });

    test('en el último paso, «Bien» se gradúa: 1 día y 1 repetición', () {
      final result = next(learning(1), ReviewGrade.good);

      expect(result.learningStep, isNull);
      expect(result.intervalDays, 1);
      expect(result.repetitions, 1);
      expect(delayOf(result), const Duration(days: 1));
      expect(result.phase, CardPhase.review);
    });

    test('en el último paso, «Difícil» repite el paso: 10 minutos', () {
      final result = next(learning(1), ReviewGrade.hard);

      expect(result.learningStep, 1);
      expect(delayOf(result), const Duration(minutes: 10));
    });

    test('en el último paso, «De nuevo» vuelve al paso 0: 1 minuto', () {
      final result = next(learning(1), ReviewGrade.again);

      expect(result.learningStep, 0);
      expect(delayOf(result), const Duration(minutes: 1));
    });

    test('en el último paso, «Fácil» se gradúa a 4 días', () {
      final result = next(learning(1), ReviewGrade.easy);

      expect(result.learningStep, isNull);
      expect(result.intervalDays, 4);
      expect(delayOf(result), const Duration(days: 4));
    });

    test('«Difícil» nunca es igual a «De nuevo»', () {
      for (final c in [newCard(), learning(0), learning(1), relearning()]) {
        expect(
          delayOf(next(c, ReviewGrade.hard)),
          greaterThan(delayOf(next(c, ReviewGrade.again))),
          reason: '${c.phase} paso ${c.learningStep}',
        );
      }
    });

    test('recorrido: nueva → Bien → Bien → repasada a 1 día → Bien a 6 días '
        '→ Bien a 15', () {
      var c = newCard();
      c = scheduleNext(c, ReviewGrade.good, now: now); // 10 min
      expect(c.phase, CardPhase.learning);
      final later = c.dueAt;
      c = scheduleNext(c, ReviewGrade.good, now: later); // se gradúa
      expect(c.phase, CardPhase.review);
      expect(c.intervalDays, 1);
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt);
      expect(c.intervalDays, 6);
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt);
      expect(c.intervalDays, 15);
      expect(c.easeFactor, 2.5);
    });

    test('recorrido: olvidar a mitad de camino vuelve al principio', () {
      var c = newCard();
      c = scheduleNext(c, ReviewGrade.good, now: now); // paso 1
      c = scheduleNext(c, ReviewGrade.again, now: c.dueAt); // paso 0
      expect(c.learningStep, 0);
      expect(c.dueAt.difference(c.lastReviewedAt!), const Duration(minutes: 1));
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt); // paso 1
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt); // se gradúa
      expect(c.phase, CardPhase.review);
      expect(c.repetitions, 1);
    });
  });

  group('un repaso en días (SM-2)', () {
    test('el segundo repaso exitoso salta a 6 días', () {
      final result = next(
        inReview(repetitions: 1, intervalDays: 1),
        ReviewGrade.good,
      );

      expect(result.repetitions, 2);
      expect(result.intervalDays, 6);
    });

    test('del tercer repaso en adelante, el intervalo anterior se multiplica '
        'por el factor de facilidad', () {
      final result = next(
        inReview(repetitions: 2, intervalDays: 6),
        ReviewGrade.good,
      );

      // "Bien" (quality 4) deja el factor de facilidad prácticamente sin
      // cambios (2.5 -> 2.5), así que el intervalo pasa a ser 6 * 2.5 = 15.
      expect(result.repetitions, 3);
      expect(result.intervalDays, 15);
      expect(delayOf(result), const Duration(days: 15));
      expect(result.learningStep, isNull);
    });

    test('«De nuevo» es un olvido: reinicia las repeticiones, baja la '
        'facilidad y pasa a reaprender en 10 minutos', () {
      final avanzada = inReview(
        repetitions: 5,
        intervalDays: 60,
        easeFactor: 2.8,
      );

      final result = next(avanzada, ReviewGrade.again);

      expect(result.repetitions, 0);
      expect(result.intervalDays, 1);
      expect(result.learningStep, 0);
      expect(result.phase, CardPhase.relearning);
      expect(delayOf(result), const Duration(minutes: 10));
      expect(result.easeFactor, lessThan(2.8));
    });

    test('«Fácil» sube la facilidad; «Difícil» la baja pero cuenta como '
        'repaso exitoso', () {
      final base = inReview(repetitions: 1, intervalDays: 1);

      expect(next(base, ReviewGrade.easy).easeFactor, greaterThan(2.5));
      final hard = next(base, ReviewGrade.hard);
      expect(hard.easeFactor, lessThan(2.5));
      expect(hard.repetitions, 2);
      expect(hard.intervalDays, 6);
    });

    test(
      'la facilidad nunca baja de 1.3, el piso que define el propio SM-2',
      () {
        var c = inReview(easeFactor: 1.3);

        // Muchos olvidos seguidos (pasando cada vez por reaprender) no deberían
        // poder perforar el piso.
        for (var i = 0; i < 10; i++) {
          c = scheduleNext(c, ReviewGrade.again, now: now);
          c = scheduleNext(c, ReviewGrade.good, now: c.dueAt); // reaprende
          c = scheduleNext(c, ReviewGrade.hard, now: c.dueAt); // y a repasar
        }

        expect(c.easeFactor, greaterThanOrEqualTo(1.3));
      },
    );

    test('el intervalo tiene tope (100 años): sin él, contestar «Fácil» muchas '
        'veces desborda la fecha y la tarjeta vuelve ya', () {
      var c = inReview(repetitions: 5, intervalDays: 30000);

      c = next(c, ReviewGrade.easy);

      expect(c.intervalDays, kMaxIntervalDays);
      expect(c.dueAt.isAfter(now), isTrue);
      // Y se mantiene en el tope, repaso tras repaso.
      for (var i = 0; i < 100; i++) {
        c = scheduleNext(c, ReviewGrade.easy, now: c.dueAt);
        expect(c.intervalDays, kMaxIntervalDays);
        expect(c.dueAt.isAfter(c.lastReviewedAt!), isTrue);
      }
    });

    test('una tarjeta traída con un intervalo largo y pocas repeticiones no '
        'se achica al contestar bien', () {
      final imported = inReview(repetitions: 1, intervalDays: 30);

      final result = next(imported, ReviewGrade.good);

      expect(result.intervalDays, greaterThanOrEqualTo(30));
    });
  });

  group('una tarjeta que se olvidó y se reaprende', () {
    test('«De nuevo» repite el paso: 10 minutos, sin tocar la facilidad', () {
      final result = next(relearning(), ReviewGrade.again);

      expect(result.learningStep, 0);
      expect(delayOf(result), const Duration(minutes: 10));
      expect(result.easeFactor, 1.7);
    });

    test('«Difícil» lo estira a 15 minutos', () {
      final result = next(relearning(), ReviewGrade.hard);

      expect(result.learningStep, 0);
      expect(delayOf(result), const Duration(minutes: 15));
    });

    test('«Bien» vuelve a la cola de días: 1 día y 1 repetición', () {
      final result = next(relearning(), ReviewGrade.good);

      expect(result.learningStep, isNull);
      expect(result.phase, CardPhase.review);
      expect(result.intervalDays, 1);
      expect(result.repetitions, 1);
      expect(delayOf(result), const Duration(days: 1));
      expect(result.easeFactor, 1.7);
    });

    test('«Fácil» vuelve con un día más: 2 días', () {
      final result = next(relearning(), ReviewGrade.easy);

      expect(result.learningStep, isNull);
      expect(result.intervalDays, 2);
      expect(delayOf(result), const Duration(days: 2));
    });

    test('conserva el intervalo que dejó el olvido, sea cual sea', () {
      final result = next(relearning(intervalDays: 3), ReviewGrade.good);

      expect(result.intervalDays, 3);
    });

    test('recorrido completo de un olvido: repaso → De nuevo → Bien → 1 día '
        '→ Bien → 6 días', () {
      var c = inReview(repetitions: 4, intervalDays: 40);
      c = scheduleNext(c, ReviewGrade.again, now: now);
      expect(c.phase, CardPhase.relearning);
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt);
      expect(c.phase, CardPhase.review);
      expect(c.intervalDays, 1);
      c = scheduleNext(c, ReviewGrade.good, now: c.dueAt);
      expect(c.intervalDays, 6);
    });
  });

  group('lo ya programado no cambia (la tarjeta de antes de F31)', () {
    test('un repaso en días con su fecha y su facilidad sigue el SM-2 de '
        'siempre', () {
      final legacy = card(
        repetitions: 4,
        intervalDays: 30,
        easeFactor: 2.2,
        lastReviewedAt: now.subtract(const Duration(days: 30)),
      );

      final good = next(legacy, ReviewGrade.good);
      final easy = next(legacy, ReviewGrade.easy);
      final hard = next(legacy, ReviewGrade.hard);

      expect(good.intervalDays, 66); // 30 * 2.2
      expect(good.easeFactor, 2.2);
      expect(good.learningStep, isNull);
      expect(easy.intervalDays, (30 * 2.3).round());
      expect(hard.intervalDays, (30 * (2.2 - 0.14)).round());
    });

    test('la que se había contestado «De nuevo» (1 día, 0 repeticiones) sigue '
        'en repaso y, contestando bien, vuelve a 1 día', () {
      final lapsed = card(intervalDays: 1, lastReviewedAt: now);
      expect(lapsed.phase, CardPhase.review);

      final result = next(lapsed, ReviewGrade.good);

      expect(result.repetitions, 1);
      expect(result.intervalDays, 1);
      expect(result.learningStep, isNull);
    });
  });

  group('los pasos configurados', () {
    const custom = LearningSteps(
      learning: [
        Duration(minutes: 2),
        Duration(minutes: 20),
        Duration(hours: 1),
      ],
      relearning: [Duration(minutes: 5), Duration(minutes: 30)],
      graduatingIntervalDays: 2,
      easyIntervalDays: 7,
    );

    test('recorren todos los pasos antes de graduar', () {
      var c = newCard();
      final delays = <Duration>[];
      while (c.phase != CardPhase.review) {
        c = scheduleNext(c, ReviewGrade.good, now: now, steps: custom);
        delays.add(delayOf(c));
      }

      expect(delays, [
        const Duration(minutes: 20), // paso 1
        const Duration(hours: 1), // paso 2
        const Duration(days: 2), // se gradúa
      ]);
      expect(c.intervalDays, 2);
    });

    test('«Difícil» en el primer paso es el promedio de los dos primeros; en '
        'otro, repite', () {
      final first = next(newCard(), ReviewGrade.hard, steps: custom);
      final second = next(learning(1), ReviewGrade.hard, steps: custom);
      final third = next(learning(2), ReviewGrade.hard, steps: custom);

      expect(delayOf(first), const Duration(minutes: 11));
      expect(delayOf(second), const Duration(minutes: 20));
      expect(delayOf(third), const Duration(hours: 1));
    });

    test('con un solo paso, «Difícil» suma la mitad, a lo sumo un día', () {
      const one = LearningSteps(
        learning: [Duration(minutes: 5)],
        relearning: [Duration(days: 3)],
      );

      expect(
        delayOf(next(newCard(), ReviewGrade.hard, steps: one)),
        const Duration(minutes: 7, seconds: 30),
      );
      expect(
        delayOf(next(relearning(), ReviewGrade.hard, steps: one)),
        const Duration(days: 4),
      );
    });

    test('«Fácil» usa el intervalo configurado, y el olvido el primer paso '
        'de reaprender', () {
      expect(
        delayOf(next(newCard(), ReviewGrade.easy, steps: custom)),
        const Duration(days: 7),
      );
      expect(
        delayOf(next(inReview(), ReviewGrade.again, steps: custom)),
        const Duration(minutes: 5),
      );
    });

    test('si los pasos se acortaron, una tarjeta en un paso que ya no está '
        'se trata como el último', () {
      final stale = learning(5);

      final result = next(stale, ReviewGrade.good);

      expect(result.learningStep, isNull);
      expect(result.phase, CardPhase.review);
    });

    test('sin pasos no hay calendario: se rechaza', () {
      const empty = LearningSteps(learning: []);

      expect(
        () => next(newCard(), ReviewGrade.good, steps: empty),
        throwsArgumentError,
      );
    });
  });

  group('en cualquier recorrido', () {
    /// Un recorrido largo y determinista: [seed] fija las respuestas, y el
    /// tiempo avanza hasta el momento en que la tarjeta vuelve (a veces con
    /// atraso).
    List<Flashcard> walk(int seed, {int steps = 3000}) {
      final random = math.Random(seed);
      var c = newCard();
      var at = now;
      final path = <Flashcard>[c];
      for (var i = 0; i < steps; i++) {
        final grade = switch (random.nextInt(10)) {
          0 => ReviewGrade.again,
          1 || 2 => ReviewGrade.hard,
          3 || 4 || 5 || 6 => ReviewGrade.good,
          _ => ReviewGrade.easy,
        };
        // A veces se contesta con atraso.
        at = c.dueAt.add(Duration(minutes: random.nextInt(3) * 90));
        c = scheduleNext(c, grade, now: at);
        path.add(c);
      }
      return path;
    }

    test('la fecha siempre queda después del momento del repaso', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        final path = walk(seed);
        for (var i = 1; i < path.length; i++) {
          expect(
            path[i].dueAt.isAfter(path[i].lastReviewedAt!),
            isTrue,
            reason: 'seed $seed, paso $i',
          );
        }
      }
    });

    test('la facilidad nunca baja de 1.3 ni sube sin límite razonable', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        for (final c in walk(seed)) {
          expect(c.easeFactor, greaterThanOrEqualTo(1.3), reason: '$seed');
          expect(c.easeFactor, lessThan(10), reason: '$seed');
        }
      }
    });

    test(
      'un paso cabe en los pasos, y solo existe en aprender o reaprender',
      () {
        for (final seed in [1, 2, 3, 4, 5]) {
          for (final c in walk(seed)) {
            final step = c.learningStep;
            if (step != null) {
              expect(step, inInclusiveRange(0, 1), reason: '$seed');
              // Vuelve en minutos, nunca en días.
              expect(
                c.dueAt.difference(c.lastReviewedAt!),
                lessThanOrEqualTo(const Duration(minutes: 15)),
                reason: 'seed $seed',
              );
            }
            if (c.phase == CardPhase.relearning) {
              expect(c.learningStep, 0);
              expect(c.intervalDays, greaterThanOrEqualTo(1));
            }
            if (c.phase == CardPhase.learning) {
              expect(c.intervalDays, 0);
            }
          }
        }
      },
    );

    test('nunca un intervalo menor a lo debido: al contestar bien o fácil un '
        'repaso, el intervalo no baja', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        final path = walk(seed);
        // Reconstruir cada paso con la respuesta es caro de inferir, así que
        // se prueba directo: cualquier tarjeta del recorrido que esté en
        // repaso, contestada bien o fácil, no achica su intervalo.
        for (final c in path) {
          if (c.phase != CardPhase.review || c.intervalDays < 1) continue;
          for (final grade in [ReviewGrade.good, ReviewGrade.easy]) {
            final result = scheduleNext(c, grade, now: c.dueAt);
            expect(
              result.intervalDays,
              greaterThanOrEqualTo(c.intervalDays),
              reason: 'seed $seed, ${c.repetitions} rep, ${c.intervalDays} d',
            );
          }
        }
      }
    });

    test('«Fácil» nunca vuelve antes que «Bien», en ninguna etapa', () {
      for (final seed in [1, 2, 3]) {
        for (final c in walk(seed, steps: 600)) {
          final good = scheduleNext(c, ReviewGrade.good, now: c.dueAt);
          final easy = scheduleNext(c, ReviewGrade.easy, now: c.dueAt);
          expect(
            easy.dueAt.isBefore(good.dueAt),
            isFalse,
            reason: 'seed $seed, ${c.phase}, paso ${c.learningStep}',
          );
        }
      }
    });

    test('«De nuevo» nunca vuelve después que cualquier otra respuesta', () {
      for (final seed in [1, 2, 3]) {
        for (final c in walk(seed, steps: 600)) {
          final again = scheduleNext(c, ReviewGrade.again, now: c.dueAt);
          for (final other in [
            ReviewGrade.hard,
            ReviewGrade.good,
            ReviewGrade.easy,
          ]) {
            final result = scheduleNext(c, other, now: c.dueAt);
            expect(
              again.dueAt.isAfter(result.dueAt),
              isFalse,
              reason: 'seed $seed, ${c.phase}, $other',
            );
          }
        }
      }
    });

    test('es determinista: lo mismo con lo mismo da lo mismo', () {
      final a = walk(7);
      final b = walk(7);

      expect(a, b);
    });

    test('no cambia nada fuera del calendario', () {
      final original = card(
        repetitions: 3,
        intervalDays: 15,
        lastReviewedAt: now,
      ).copyWith(suspended: true, groupId: 'g', clozeIndex: 2);

      for (final grade in ReviewGrade.values) {
        final result = next(original, grade);
        expect(result.id, original.id);
        expect(result.front, original.front);
        expect(result.suspended, isTrue);
        expect(result.groupId, 'g');
        expect(result.clozeIndex, 2);
        expect(result.createdAt, original.createdAt);
      }
    });

    test('no muta la tarjeta que recibe', () {
      final original = newCard();
      final copy = original.copyWith();

      for (final grade in ReviewGrade.values) {
        next(original, grade);
      }

      expect(original, copy);
    });
  });

  group('la calidad de cada nota (F11)', () {
    test('las cuatro notas de repaso y su calidad en SM-2', () {
      expect(qualityOf(ReviewGrade.again), 0);
      expect(qualityOf(ReviewGrade.hard), 3);
      expect(qualityOf(ReviewGrade.good), 4);
      expect(qualityOf(ReviewGrade.easy), 5);
    });

    test('es la que usa el planificador: una nota por debajo de 3 reinicia la '
        'repetición de un repaso y una de 3 o más, no', () {
      final c = inReview(repetitions: 4, intervalDays: 30);

      for (final grade in ReviewGrade.values) {
        final result = next(c, grade);
        expect(
          result.repetitions == 0,
          qualityOf(grade) < 3,
          reason: grade.name,
        );
      }
    });
  });
}
