import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_answer_grader.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_session.dart';
import 'package:sinapsis/features/transform/domain/entities/cancellation_signal.dart';

import '../flashcards/support/study_fakes.dart';

const _single = QuizQuestion(
  id: 'q1',
  type: QuizQuestionType.single,
  prompt: '¿Quién?',
  options: [
    QuizOption(text: 'Aarón', correct: false),
    QuizOption(text: 'Moisés', correct: true),
  ],
);

const _multiple = QuizQuestion(
  id: 'q2',
  type: QuizQuestionType.multiple,
  prompt: '¿Cuáles?',
  options: [
    QuizOption(text: 'a', correct: true),
    QuizOption(text: 'b', correct: false),
    QuizOption(text: 'c', correct: true),
  ],
);

const _blank = QuizQuestion(
  id: 'q3',
  type: QuizQuestionType.fillBlank,
  prompt: 'El pueblo llega al $kQuizBlank.',
  answer: 'Monte Sinaí',
  alternatives: ['Horeb'],
);

const _short = QuizQuestion(
  id: 'q4',
  type: QuizQuestionType.shortAnswer,
  prompt: '¿Por qué salen?',
  answer: 'Para dejar la esclavitud.',
  explanation: 'Eran esclavos.',
);

const _quiz = Quiz(title: 'Q', questions: [_single, _multiple, _blank, _short]);

void main() {
  group('calificar', () {
    test('opción única y selección múltiple: exactamente las correctas', () {
      expect(gradeQuizChoice(_single, {1}), QuizVerdict.correct);
      expect(gradeQuizChoice(_single, {0}), QuizVerdict.wrong);
      expect(gradeQuizChoice(_multiple, {0, 2}), QuizVerdict.correct);
      expect(gradeQuizChoice(_multiple, {0}), QuizVerdict.wrong);
      expect(gradeQuizChoice(_multiple, {0, 1, 2}), QuizVerdict.wrong);
      expect(gradeQuizChoice(_multiple, {}), QuizVerdict.wrong);
    });

    test('completar se compara sin tildes ni mayúsculas, y con sus otras '
        'formas', () {
      for (final typed in [
        'monte sinai',
        'MONTE SINAÍ',
        ' Monte  Sinaí. ',
        'horeb',
      ]) {
        expect(
          gradeQuizBlank(_blank, typed).verdict,
          QuizVerdict.correct,
          reason: typed,
        );
      }
      expect(gradeQuizBlank(_blank, 'Egipto').verdict, QuizVerdict.wrong);
      expect(gradeQuizBlank(_blank, '').verdict, QuizVerdict.wrong);
    });

    test('un descuido de tipeo es un «casi»: lo decide la persona', () {
      final graded = gradeQuizBlank(_blank, 'monte sinia');
      expect(graded.verdict, isNull);
      expect(graded.comparison.verdict.name, 'close');
    });
  });

  group('una vuelta', () {
    test('responder, avanzar, volver y el puntaje', () {
      var run = QuizRun.start(_quiz);
      expect(run.current, _single);
      expect(run.isFirst, isTrue);

      run = run.answer(
        const QuizChoiceAnswer(chosen: {1}, verdict: QuizVerdict.correct),
      );
      // Una respondida no cambia.
      run = run.answer(
        const QuizChoiceAnswer(chosen: {0}, verdict: QuizVerdict.wrong),
      );
      expect(run.currentAnswer!.isCorrect, isTrue);

      run = run.next();
      expect(run.current, _multiple);
      run = run.answer(
        const QuizChoiceAnswer(chosen: {0}, verdict: QuizVerdict.wrong),
      );
      run = run.previous();
      expect(run.current, _single);
      expect(run.previous().index, 0);

      run = run.next().next().next();
      expect(run.isLast, isTrue);
      expect(run.finished, isFalse);
      run = run.next();
      expect(run.finished, isTrue);
      expect(run.correct, 1);
      expect(run.total, 4);
    });

    test('«Repetir solo las que fallé»: las falladas y las salteadas, en '
        'orden, desde cero', () {
      var run = QuizRun.start(_quiz)
          .answer(
            const QuizChoiceAnswer(chosen: {1}, verdict: QuizVerdict.correct),
          )
          .next()
          .answer(
            const QuizChoiceAnswer(chosen: {1}, verdict: QuizVerdict.wrong),
          )
          .next()
          .answer(
            const QuizTypedAnswer(typed: 'horeb', verdict: QuizVerdict.correct),
          )
          .next()
          .next();
      expect(run.missed, [_multiple, _short]);

      run = run.retryMissed();
      expect(run.retry, isTrue);
      expect(run.finished, isFalse);
      expect(run.questions, [_multiple, _short]);
      expect(run.answers, isEmpty);
      expect(run.index, 0);

      run = run
          .answer(
            const QuizChoiceAnswer(
              chosen: {0, 2},
              verdict: QuizVerdict.correct,
            ),
          )
          .next()
          .answer(
            const QuizTypedAnswer(typed: 'x', verdict: QuizVerdict.correct),
          )
          .next();
      expect(run.missed, isEmpty);
      // Sin nada fallado, repetir no hace nada.
      expect(run.retryMissed(), same(run));
    });

    test('recalificar cambia la de ahora: el «casi» que decide la persona', () {
      var run = QuizRun.start(_quiz).next().next();
      run = run.regrade(
        const QuizTypedAnswer(
          typed: 'monte sinia',
          verdict: QuizVerdict.correct,
          by: QuizGrader.self,
        ),
      );
      expect(run.currentAnswer!.isCorrect, isTrue);
    });
  });

  group('la IA revisa la respuesta breve', () {
    QuizAnswerGrader grader(
      FakeModelWriter writer, {
      LanguageModelStatus status = const LanguageModelReady(
        provider: AiProvider.gemini,
      ),
    }) => QuizAnswerGrader(
      writer: () => writer,
      readiness: () =>
          ({bool background = false}) async => status,
    );

    test('con la pregunta, lo esperado y lo escrito; dice si está bien y por '
        'qué, en el idioma del cuestionario', () async {
      final writer = FakeModelWriter(
        inOrder(['{"correcta": true, "razon": "Dice lo esencial."}']),
      );

      final grade = await grader(writer).grade(
        question: _short,
        typed: 'Porque eran esclavos',
        languageCode: 'en',
      );

      expect(grade.correct, isTrue);
      expect(grade.reason, 'Dice lo esencial.');
      final call = writer.calls.single;
      expect(call.material, contains('Pregunta: ¿Por qué salen?'));
      expect(call.material, contains('Respuesta esperada: Para dejar'));
      expect(call.material, contains('Respuesta de la persona: Porque eran'));
      expect(call.instruction, contains('inglés'));
      expect(call.maxOutputTokens, QuizAnswerGrader.replyTokens);
    });

    test(
      'una respuesta rota se corrige una vez; si tampoco, no se puede leer',
      () async {
        final fixed = FakeModelWriter(inOrder(['mmm', '{"correct": "no"}']));
        expect(
          (await grader(
            fixed,
          ).grade(question: _short, typed: 'x', languageCode: 'es')).correct,
          isFalse,
        );

        final broken = FakeModelWriter(inOrder(['mmm']));
        await expectLater(
          grader(
            broken,
          ).grade(question: _short, typed: 'x', languageCode: 'es'),
          throwsA(isA<UnreadableStructuredReply>()),
        );
      },
    );

    test('se cancela', () async {
      final signal = CancellationSignal()..cancel();
      final writer = FakeModelWriter(inOrder(['{"correcta": true}']));
      await expectLater(
        grader(writer).grade(
          question: _short,
          typed: 'x',
          languageCode: 'es',
          cancellation: signal,
        ),
        throwsA(isA<CreationCancelledException>()),
      );
      expect(writer.calls, isEmpty);
    });

    test('sin un modelo listo, no está a mano: se autocalifica', () async {
      final writer = FakeModelWriter(inOrder(['{}']));
      expect(await grader(writer).isAvailable(), isTrue);
      expect(
        await grader(
          writer,
          status: const LanguageModelNeedsDownload(),
        ).isAvailable(),
        isFalse,
      );
      final failing = QuizAnswerGrader(
        writer: () => writer,
        readiness: () =>
            ({bool background = false}) async => throw StateError('x'),
      );
      expect(await failing.isAvailable(), isFalse);
    });

    test('lee el sí o no de muchas maneras, y sin él falla', () {
      expect(
        parseQuizGrade({'is_correct': 1, 'feedback': 'bien'}).reason,
        'bien',
      );
      expect(parseQuizGrade({'Correcta': 'sí'}).correct, isTrue);
      expect(() => parseQuizGrade({'razon': 'x'}), throwsFormatException);
      expect(() => parseQuizGrade([1]), throwsFormatException);
    });
  });
}
