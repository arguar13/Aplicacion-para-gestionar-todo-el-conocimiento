import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// Una respuesta de la vuelta: a qué tarjeta del mazo (su lugar), con qué
/// calificación y si fue de práctica —sin calendario— o al calendario de
/// verdad de su tarjeta.
typedef DeckRoundAnswer = ({int card, ReviewGrade grade, bool practice});

/// Una vuelta por el mazo de «Tarjetas didácticas», como en Anki (F43, M13,
/// decisión M): se ve la pregunta, se muestra la respuesta y se califica con
/// De nuevo, Difícil, Bien o Fácil. «De nuevo» la vuelve a poner al final de
/// la vuelta; las demás la dan por vista.
///
/// Inmutable, como la vuelta del cuestionario (`QuizRun`): cada paso da otra
/// y el visor solo la dibuja. Guardar la calificación en el calendario no es
/// cosa suya: lo hace el visor con el repositorio de siempre, y acá se anota
/// si fue de verdad o de práctica.
@immutable
class DeckRound {
  const DeckRound._({
    required this.queue,
    required this.answers,
    required this.revealed,
    required this.shuffled,
    required this.size,
  });

  /// Una vuelta por las [count] tarjetas de un mazo, en su orden.
  factory DeckRound.start(int count) => DeckRound._(
    queue: [for (var i = 0; i < count; i++) i],
    answers: const [],
    revealed: false,
    shuffled: false,
    size: count,
  );

  /// Otra vuelta solo con [cards] (los lugares en el mazo), en ese orden.
  factory DeckRound.only(List<int> cards) => DeckRound._(
    queue: List.unmodifiable(cards),
    answers: const [],
    revealed: false,
    shuffled: false,
    size: cards.length,
  );

  /// Lo que falta, por su lugar en el mazo: la primera es la que se ve.
  final List<int> queue;

  /// Lo respondido en esta vuelta, de la más vieja a la más nueva.
  final List<DeckRoundAnswer> answers;

  /// Si la que se ve ya tiene la respuesta a la vista.
  final bool revealed;

  /// Si lo que falta va barajado.
  final bool shuffled;

  /// Cuántas tarjetas distintas tiene la vuelta.
  final int size;

  /// Si ya no queda ninguna.
  bool get finished => queue.isEmpty;

  /// La que se ve, por su lugar en el mazo.
  int get current => queue.first;

  /// Cuántas respuestas lleva: «3 / 18» es la siguiente de estas.
  int get done => answers.length;

  /// Lo contestado más lo que falta. Una que vuelve por «De nuevo» cuenta otra
  /// vez, así que puede crecer: dice la verdad de lo que falta, como el
  /// avance de la sesión de Repasar.
  int get total => done + queue.length;

  /// Cuántas respuestas fueron a cada botón.
  Map<ReviewGrade, int> get tally => {
    for (final grade in ReviewGrade.values)
      grade: answers.where((a) => a.grade == grade).length,
  };

  /// Las que fueron a «De nuevo» alguna vez, sin repetir y en el orden en que
  /// se vieron: lo de «Repasar las de "De nuevo"».
  List<int> get forgotten => [
    ...{
      for (final answer in answers)
        if (answer.grade == ReviewGrade.again) answer.card,
    },
  ];

  /// Cuántas respuestas fueron de práctica.
  int get practiced => answers.where((a) => a.practice).length;

  /// Muestra la respuesta de la que se ve.
  DeckRound reveal() => finished || revealed ? this : _copy(revealed: true);

  /// Califica la que se ve —con la respuesta a la vista— y pasa a la
  /// siguiente. «De nuevo» la pone al final de lo que falta.
  DeckRound grade(ReviewGrade grade, {required bool practice}) {
    if (finished || !revealed) return this;
    final card = current;
    return _copy(
      queue: [...queue.skip(1), if (grade == ReviewGrade.again) card],
      answers: [...answers, (card: card, grade: grade, practice: practice)],
      revealed: false,
    );
  }

  /// Baraja lo que falta, o lo vuelve al orden del mazo, **sin sacar la que
  /// se ve** ni taparle la respuesta.
  DeckRound toggleShuffle([math.Random? random]) {
    if (queue.length < 2) return _copy(shuffled: !shuffled);
    final rest = queue.skip(1).toList();
    if (shuffled) {
      rest.sort();
    } else {
      rest.shuffle(random ?? math.Random());
    }
    return _copy(queue: [current, ...rest], shuffled: !shuffled);
  }

  DeckRound _copy({
    List<int>? queue,
    List<DeckRoundAnswer>? answers,
    bool? revealed,
    bool? shuffled,
  }) => DeckRound._(
    queue: queue == null ? this.queue : List.unmodifiable(queue),
    answers: answers == null ? this.answers : List.unmodifiable(answers),
    revealed: revealed ?? this.revealed,
    shuffled: shuffled ?? this.shuffled,
    size: size,
  );
}
