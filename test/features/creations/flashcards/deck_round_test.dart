import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/creations/flashcards/domain/deck_round.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';

/// La vuelta por el mazo, como en Anki (F43, M13): la respuesta se muestra
/// antes de calificar, «De nuevo» la vuelve a poner al final, y al terminar
/// se sabe cuántas fueron a cada botón.
void main() {
  test('sin la respuesta a la vista no se califica', () {
    final round = DeckRound.start(3);
    expect(round.grade(ReviewGrade.good, practice: false), same(round));
    expect(round.reveal().revealed, isTrue);
  });

  test('cada calificación pasa a la siguiente, del frente', () {
    final round = DeckRound.start(
      3,
    ).reveal().grade(ReviewGrade.good, practice: false);
    expect(round.current, 1);
    expect(round.revealed, isFalse);
    expect(round.done, 1);
    expect(round.total, 3);
  });

  test('«De nuevo» la vuelve a poner al final de la vuelta, y cuenta otra '
      'vez', () {
    var round = DeckRound.start(
      3,
    ).reveal().grade(ReviewGrade.again, practice: false);
    expect(round.queue, [1, 2, 0]);
    expect(round.total, 4);
    round = round
        .reveal()
        .grade(ReviewGrade.easy, practice: false)
        .reveal()
        .grade(ReviewGrade.hard, practice: false);
    expect(round.current, 0);
    round = round.reveal().grade(ReviewGrade.good, practice: false);
    expect(round.finished, isTrue);
    expect(round.tally, {
      ReviewGrade.again: 1,
      ReviewGrade.hard: 1,
      ReviewGrade.good: 1,
      ReviewGrade.easy: 1,
    });
    expect(round.forgotten, [0]);
    expect(round.size, 3);
  });

  test('anota lo que fue de práctica', () {
    final round = DeckRound.start(2)
        .reveal()
        .grade(ReviewGrade.good, practice: true)
        .reveal()
        .grade(ReviewGrade.good, practice: false);
    expect(round.practiced, 1);
  });

  test('barajar no saca la que se ve ni le tapa la respuesta; volver al '
      'orden ordena lo que falta', () {
    final revealed = DeckRound.start(
      6,
    ).reveal().grade(ReviewGrade.good, practice: false).reveal();
    final shuffled = revealed.toggleShuffle(math.Random(3));
    expect(shuffled.current, 1);
    expect(shuffled.revealed, isTrue);
    expect(shuffled.shuffled, isTrue);
    expect(shuffled.queue.toSet(), {1, 2, 3, 4, 5});
    final back = shuffled.toggleShuffle();
    expect(back.queue, [1, 2, 3, 4, 5]);
    expect(back.shuffled, isFalse);
  });

  test('otra vuelta solo con las de «De nuevo»', () {
    final round = DeckRound.only(const [4, 1]);
    expect(round.queue, [4, 1]);
    expect(round.size, 2);
    expect(round.done, 0);
  });
}
