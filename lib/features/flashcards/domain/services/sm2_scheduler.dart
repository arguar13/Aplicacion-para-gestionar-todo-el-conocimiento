import 'dart:math' as math;

import 'package:sinapsis/core/domain/entities/card_phase.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/flashcards/domain/services/learning_steps.dart';

/// El calendario de repaso: SM-2 de Piotr Wozniak (1987) para los repasos en
/// días, más los pasos de aprendizaje de Anki para lo nuevo y lo olvidado
/// (F31, decisión 69).
///
/// A partir de cómo salió un repaso, decide cuándo vuelve la tarjeta: en
/// minutos, si se está aprendiendo, o en días, si ya se repasa.
///
/// Función pura y sin estado a propósito —recibe la tarjeta, devuelve la
/// tarjeta siguiente— para poder probarla sin una base de datos de por
/// medio: la lógica de cuándo repasar algo no debería depender de que haya
/// una fila real en SQLite.
///
/// ## La máquina de estados
///
/// La etapa sale de la tarjeta (`Flashcard.phase`); con los pasos por defecto
/// ([LearningSteps.standard]) es esta:
///
/// - **Nueva** y **aprendiendo en el paso 0**: «De nuevo» → paso 0, 1 min;
///   «Difícil» → paso 0, 6 min; «Bien» → paso 1, 10 min; «Fácil» → se
///   gradúa a 4 días.
/// - **Aprendiendo en el paso 1** (el último): «De nuevo» → paso 0, 1 min;
///   «Difícil» → paso 1, 10 min; «Bien» → se gradúa a 1 día; «Fácil» → se
///   gradúa a 4 días.
/// - **Repaso** (en días): «De nuevo» es un olvido —baja la facilidad y pasa
///   a reaprender, paso 0, 10 min—; las otras tres son el SM-2 de siempre
///   («Difícil» baja la facilidad, «Fácil» la sube).
/// - **Reaprendiendo**: «De nuevo» → paso 0, 10 min; «Difícil» → paso 0, 15
///   min; «Bien» → se gradúa a 1 día; «Fácil» → se gradúa a 2 días.
///
/// - «Se gradúa» es salir de los pasos: sin paso, con el intervalo dicho, que
///   vence en esa cantidad de días. Al graduar de aprender quedan 1
///   repetición (con «Bien») o 2 (con «Fácil», que se salta el primer
///   escalón de 1 y 6 días); al graduar de reaprender, 1.
/// - «Difícil» en el primer paso de varios es el promedio de ese paso y el
///   siguiente (11 / 2 = 5,5 → 6 min); en un paso que no es el primero repite
///   el paso; en el único paso de la lista (el de reaprender), lo estira a 1,5
///   veces (10 → 15 min). Así «Difícil» nunca es igual a «De nuevo».
/// - Aprender y reaprender no tocan la facilidad: solo un repaso en días lo
///   hace.
/// - **Lo ya programado no cambia**: toda tarjeta de antes de F31 es de
///   «Repaso» (o nueva), y el repaso en días es el SM-2 de siempre. Lo único
///   distinto es que ahora «De nuevo» en un repaso pasa por el paso de
///   reaprendizaje, y de ahí a 1 día.
Flashcard scheduleNext(
  Flashcard card,
  ReviewGrade grade, {
  required DateTime now,
  LearningSteps steps = LearningSteps.standard,
}) {
  if (steps.learning.isEmpty || steps.relearning.isEmpty) {
    throw ArgumentError.value(
      steps,
      'steps',
      'Hace falta al menos un paso de aprendizaje y uno de reaprendizaje.',
    );
  }
  return switch (card.phase) {
    CardPhase.newCard ||
    CardPhase.learning => _learn(card, grade, now, steps, relearning: false),
    CardPhase.relearning => _learn(card, grade, now, steps, relearning: true),
    CardPhase.review => _review(card, grade, now, steps),
  };
}

/// Una tarjeta en un paso corto: nueva, aprendiéndose o reaprendiéndose.
Flashcard _learn(
  Flashcard card,
  ReviewGrade grade,
  DateTime now,
  LearningSteps steps, {
  required bool relearning,
}) {
  final list = relearning ? steps.relearning : steps.learning;
  // Una tarjeta nueva se muestra «en el paso 0»; si los pasos se acortaron
  // desde que se guardó, no se pasa del último.
  final index = math.min(card.learningStep ?? 0, list.length - 1);

  Flashcard stay(int step, Duration delay) => card.copyWith(
    learningStep: step,
    dueAt: now.add(delay),
    lastReviewedAt: now,
  );

  Flashcard graduate({required int interval, required int repetitions}) =>
      card.copyWith(
        learningStep: null,
        intervalDays: interval,
        repetitions: repetitions,
        dueAt: now.add(Duration(days: interval)),
        lastReviewedAt: now,
      );

  // Al salir de reaprender conserva el intervalo que dejó el olvido (1 día).
  final lapsedInterval = math.max(card.intervalDays, 1);

  switch (grade) {
    case ReviewGrade.again:
      return stay(0, list.first);
    case ReviewGrade.hard:
      return stay(index, _hardDelay(list, index));
    case ReviewGrade.good:
      if (index + 1 < list.length) return stay(index + 1, list[index + 1]);
      return relearning
          ? graduate(interval: lapsedInterval, repetitions: 1)
          : graduate(interval: steps.graduatingIntervalDays, repetitions: 1);
    case ReviewGrade.easy:
      return relearning
          ? graduate(interval: lapsedInterval + 1, repetitions: 1)
          : graduate(interval: steps.easyIntervalDays, repetitions: 2);
  }
}

/// Cuánto tarda en volver una tarjeta a la que le dijeron «Difícil» en el paso
/// [index] de [list]. Ver la tabla de [scheduleNext].
Duration _hardDelay(List<Duration> list, int index) {
  if (list.length == 1) {
    final step = list.single;
    final extra = Duration(
      microseconds: math.min(
        step.inMicroseconds ~/ 2,
        const Duration(days: 1).inMicroseconds,
      ),
    );
    return step + extra;
  }
  if (index == 0) {
    final average = list[0] + list[1];
    // La mitad, redondeada hacia arriba al minuto.
    return Duration(minutes: (average.inSeconds / 120).ceil());
  }
  return list[index];
}

/// Una tarjeta que se repasa en días: SM-2, sin tocar.
Flashcard _review(
  Flashcard card,
  ReviewGrade grade,
  DateTime now,
  LearningSteps steps,
) {
  final quality = qualityOf(grade);
  final nextEase = _nextEase(card.easeFactor, quality);

  // Quality < 3 (no se recordó, "de nuevo"): SM-2 reinicia la tarjeta como
  // si fuera nueva, sin importar cuánto había crecido el intervalo antes.
  // Es lo que evita que una tarjeta que se olvidó vuelva a aparecer recién
  // en dos meses porque acumuló muchos repasos exitosos en el pasado. Desde
  // F31 pasa antes por el paso de reaprendizaje (10 min), y recién de ahí
  // vuelve a la cola de días, con 1 día de intervalo.
  if (quality < 3) {
    return card.copyWith(
      repetitions: 0,
      intervalDays: 1,
      learningStep: 0,
      easeFactor: nextEase,
      dueAt: now.add(steps.relearning.first),
      lastReviewedAt: now,
    );
  }

  final nextRepetitions = card.repetitions + 1;
  final rawInterval = switch (nextRepetitions) {
    // Nunca menos de lo que la tarjeta ya tenía: una tarjeta traída de otro
    // lado con un intervalo largo y pocas repeticiones no se achica.
    1 => math.max(1, card.intervalDays),
    2 => math.max(6, card.intervalDays),
    // A partir del tercer repaso exitoso seguido, el intervalo anterior se
    // multiplica por el factor de facilidad: es lo que hace que una
    // tarjeta fácil se espacie cada vez más, en vez de crecer siempre al
    // mismo ritmo.
    _ => (card.intervalDays * nextEase).round(),
  };
  // Con tope: ver [kMaxIntervalDays].
  final nextInterval = math.min(rawInterval, kMaxIntervalDays);

  return card.copyWith(
    repetitions: nextRepetitions,
    intervalDays: nextInterval,
    learningStep: null,
    easeFactor: nextEase,
    dueAt: now.add(Duration(days: nextInterval)),
    lastReviewedAt: now,
  );
}

/// La calidad de SM-2 (0 a 5) que le corresponde a lo que eligió la persona.
///
/// Pública porque el historial de repasos guarda las dos cosas —el nombre de la
/// nota y el número que usó el algoritmo—, y el número no puede calcularse en
/// otro lado: si esta tabla cambiara, el historial diría otra cosa que el
/// algoritmo.
int qualityOf(ReviewGrade grade) => switch (grade) {
  ReviewGrade.again => 0,
  ReviewGrade.hard => 3,
  ReviewGrade.good => 4,
  ReviewGrade.easy => 5,
};

/// La fórmula original de SM-2, con el piso de 1.3 que el propio algoritmo
/// define: sin él, una racha de tarjetas difíciles podría llevar el factor
/// a valores tan bajos que el intervalo prácticamente dejara de crecer,
/// aunque la tarjeta se estuviera empezando a recordar bien.
double _nextEase(double easeFactor, int quality) {
  final next =
      easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
  return next < 1.3 ? 1.3 : next;
}
