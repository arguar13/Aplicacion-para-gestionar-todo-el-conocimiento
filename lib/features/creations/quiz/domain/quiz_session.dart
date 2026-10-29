import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/flashcards/domain/services/typed_answer.dart';

/// Cómo quedó una pregunta respondida.
enum QuizVerdict { correct, wrong }

/// Lo que se respondió en una pregunta (F43, paso 8).
@immutable
sealed class QuizAnswer {
  const QuizAnswer({required this.verdict});

  final QuizVerdict verdict;

  bool get isCorrect => verdict == QuizVerdict.correct;
}

/// Las opciones que se eligieron, por su lugar.
final class QuizChoiceAnswer extends QuizAnswer {
  const QuizChoiceAnswer({required this.chosen, required super.verdict});

  final Set<int> chosen;
}

/// Lo que se escribió, cómo se comparó y —si hizo falta— quién lo calificó.
final class QuizTypedAnswer extends QuizAnswer {
  const QuizTypedAnswer({
    required this.typed,
    required super.verdict,
    this.comparison,
    this.reason = '',
    this.by = QuizGrader.comparison,
  });

  final String typed;

  /// La comparación con lo esperado, en una de completar.
  final TypedAnswerResult? comparison;

  /// Por qué, si lo calificó la IA.
  final String reason;
  final QuizGrader by;
}

/// Quién dijo si una respuesta escrita está bien.
enum QuizGrader {
  /// La comparación sin tildes ni mayúsculas (completar).
  comparison,

  /// La IA (respuesta breve, con IA a mano).
  ai,

  /// La persona, mirando la respuesta esperada.
  self,
}

/// Si [chosen] es la respuesta de [question]: exactamente las correctas, ni
/// una más ni una menos.
QuizVerdict gradeQuizChoice(QuizQuestion question, Set<int> chosen) =>
    setEquals(chosen, question.correctIndexes) && chosen.isNotEmpty
    ? QuizVerdict.correct
    : QuizVerdict.wrong;

/// Lo escrito en una de completar, comparado con lo que falta **sin tildes ni
/// mayúsculas** —ni puntuación, ni un artículo de más— y con sus otras formas
/// que también valen: la comparación de «Escribí la respuesta» (F31).
/// `null` en el veredicto si es un «casi» (un descuido de tipeo): ahí decide
/// la persona, como en el repaso.
({TypedAnswerResult comparison, QuizVerdict? verdict}) gradeQuizBlank(
  QuizQuestion question,
  String typed,
) {
  final comparison = compareTypedAnswer(
    typed: typed,
    correct: question.answer,
    alternatives: question.alternatives,
  );
  return (
    comparison: comparison,
    verdict: switch (comparison.verdict) {
      TypedAnswerVerdict.match => QuizVerdict.correct,
      TypedAnswerVerdict.close => null,
      TypedAnswerVerdict.mismatch => QuizVerdict.wrong,
    },
  );
}

/// Una vuelta por el cuestionario (F43, paso 8): en qué pregunta se está, lo
/// respondido, el puntaje y «Repetir solo las que fallé». Inmutable: cada
/// cambio da otra, y el visor solo la dibuja.
@immutable
class QuizRun {
  const QuizRun._({
    required this.questions,
    required this.index,
    required this.answers,
    required this.finished,
    required this.retry,
  });

  /// Una vuelta por todas las de [quiz].
  factory QuizRun.start(Quiz quiz) => QuizRun._(
    questions: quiz.questions,
    index: 0,
    answers: const {},
    finished: false,
    retry: false,
  );

  /// Las preguntas de esta vuelta, en orden.
  final List<QuizQuestion> questions;

  /// En cuál se está, desde 0.
  final int index;

  /// Lo respondido en esta vuelta, por id de pregunta.
  final Map<String, QuizAnswer> answers;

  /// Si ya se vio el resultado.
  final bool finished;

  /// Si es una vuelta de «Repetir solo las que fallé».
  final bool retry;

  QuizQuestion get current => questions[index];
  QuizAnswer? get currentAnswer => answers[current.id];
  bool get isFirst => index == 0;
  bool get isLast => index == questions.length - 1;
  int get total => questions.length;

  /// Cuántas se respondieron bien.
  int get correct => answers.values.where((a) => a.isCorrect).length;

  /// Las que se respondieron mal o no se respondieron: lo de «Repetir solo
  /// las que fallé».
  List<QuizQuestion> get missed => [
    for (final question in questions)
      if (!(answers[question.id]?.isCorrect ?? false)) question,
  ];

  /// Responde la pregunta de ahora; una ya respondida no cambia.
  QuizRun answer(QuizAnswer answer) {
    if (currentAnswer != null) return this;
    return _copy(answers: {...answers, current.id: answer});
  }

  /// La de ahora, calificada de nuevo: para el «casi» que decide la persona,
  /// o la respuesta breve que la IA no pudo revisar.
  QuizRun regrade(QuizAnswer answer) =>
      _copy(answers: {...answers, current.id: answer});

  QuizRun next() => isLast ? _copy(finished: true) : _copy(index: index + 1);

  QuizRun previous() => isFirst ? this : _copy(index: index - 1);

  /// Otra vuelta solo con las que se fallaron (o se saltearon).
  QuizRun retryMissed() {
    final again = missed;
    if (again.isEmpty) return this;
    return QuizRun._(
      questions: again,
      index: 0,
      answers: const {},
      finished: false,
      retry: true,
    );
  }

  QuizRun _copy({
    int? index,
    Map<String, QuizAnswer>? answers,
    bool? finished,
  }) => QuizRun._(
    questions: questions,
    index: index ?? this.index,
    answers: answers ?? this.answers,
    finished: finished ?? this.finished,
    retry: retry,
  );
}
