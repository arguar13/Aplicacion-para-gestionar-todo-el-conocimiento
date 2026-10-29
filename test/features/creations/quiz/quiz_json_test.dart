import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_prompt.dart';

void main() {
  group('QuizJson lee con tolerancia', () {
    test('los cuatro tipos, en castellano', () {
      final quiz = QuizJson.tryDecode({
        'titulo': 'Éxodo',
        'preguntas': [
          {
            'tipo': 'opcion_unica',
            'pregunta': '¿Quién guía al pueblo?',
            'opciones': [
              {'texto': 'Moisés', 'correcta': true, 'explicacion': 'Lo dice.'},
              {'texto': 'Aarón', 'correcta': false, 'explicacion': 'Ayuda.'},
            ],
            'explicacion': 'Moisés guía.',
          },
          {
            'tipo': 'seleccion_multiple',
            'pregunta': '¿Qué pasa?',
            'opciones': [
              {'texto': 'El mar se abre', 'correcta': true},
              {'texto': 'Llegan al Sinaí', 'correcta': true},
              {'texto': 'Llueve fuego', 'correcta': false},
            ],
          },
          {
            'tipo': 'completar',
            'pregunta': 'El mar se ___ ante el pueblo.',
            'respuesta': 'abre',
            'alternativas': ['divide', 'abre'],
          },
          {
            'tipo': 'respuesta_breve',
            'pregunta': '¿Por qué salen de Egipto?',
            'respuesta': 'Para dejar la esclavitud.',
          },
        ],
      })!;

      expect(quiz.title, 'Éxodo');
      expect(quiz.questions.map((q) => q.type), QuizQuestionType.values);
      expect(quiz.questions.map((q) => q.id), ['q1', 'q2', 'q3', 'q4']);
      final single = quiz.questions[0];
      expect(single.correctIndexes, {0});
      expect(single.options.first.explanation, 'Lo dice.');
      expect(single.explanation, 'Moisés guía.');
      expect(quiz.questions[1].correctIndexes, {0, 1});
      final blank = quiz.questions[2];
      expect(blank.prompt, 'El mar se $kQuizBlank ante el pueblo.');
      expect(blank.answer, 'abre');
      expect(blank.alternatives, ['divide', 'abre']);
      expect(quiz.questions[3].answer, 'Para dejar la esclavitud.');
      expect(quiz.questions[3].options, isEmpty);
    });

    test('en inglés, con la correcta dicha aparte como letra, número o texto, '
        'y la letra que la IA le pone adelante', () {
      final quiz = QuizJson.tryDecode({
        'questions': [
          {
            'type': 'multiple_choice',
            'question': '¿Uno?',
            'options': ['A) Roma', 'B) París', 'C) Lima'],
            'correct_answer': 'B',
          },
          {
            'question': '¿Dos?',
            'choices': ['uno', 'dos', 'tres'],
            'answer': 2,
          },
          {
            'question': '¿Tres?',
            'options': ['Sol', 'Luna'],
            'correctOption': 'luna',
          },
        ],
      })!;

      expect(quiz.questions[0].type, QuizQuestionType.single);
      expect(quiz.questions[0].options.map((o) => o.text), [
        'Roma',
        'París',
        'Lima',
      ]);
      expect(quiz.questions[0].correctIndexes, {1});
      expect(quiz.questions[1].correctIndexes, {1});
      expect(quiz.questions[2].correctIndexes, {1});
    });

    test('el tipo se deduce si falta o no se puede contestar así', () {
      final quiz = QuizJson.tryDecode({
        'questions': [
          // Dice única, pero tiene dos correctas: de selección múltiple.
          {
            'type': 'single',
            'question': '¿Cuáles?',
            'options': [
              {'text': 'a', 'correct': true},
              {'text': 'b', 'correct': true},
              {'text': 'c', 'correct': false},
            ],
          },
          // Sin tipo y con espacio: de completar.
          {'question': 'Moisés sube al ...... Sinaí', 'answer': 'monte'},
          // Sin tipo, sin espacio y con respuesta: respuesta breve.
          {'question': '¿Qué es la Pascua?', 'answer': 'Una fiesta.'},
          // De completar sin espacio: el espacio va al final.
          {
            'type': 'cloze',
            'question': 'El pueblo llega al',
            'answer': 'Sinaí',
          },
        ],
      })!;

      expect(quiz.questions.map((q) => q.type), [
        QuizQuestionType.multiple,
        QuizQuestionType.fillBlank,
        QuizQuestionType.shortAnswer,
        QuizQuestionType.fillBlank,
      ]);
      expect(quiz.questions[1].prompt, 'Moisés sube al $kQuizBlank Sinaí');
      expect(quiz.questions[3].prompt, 'El pueblo llega al $kQuizBlank');
    });

    test('lo que no se puede contestar no cuenta', () {
      final quiz = QuizJson.tryDecode({
        'questions': [
          // Sin ninguna correcta ni respuesta.
          {
            'question': '¿Ninguna?',
            'options': ['a', 'b'],
          },
          // Una sola opción.
          {
            'question': '¿Una?',
            'options': [
              {'text': 'a', 'correct': true},
            ],
          },
          // Sin pregunta.
          {'answer': 'x'},
          {'question': '¿Esta sí?', 'answer': 'Sí.'},
          // Repetida, sin mayúsculas ni tildes.
          {'question': '¿esta si?', 'answer': 'Otra.'},
        ],
      })!;
      expect(quiz.questions.single.prompt, '¿Esta sí?');
    });

    test('nada que leer: null, y parse lo dice para corregirlo', () {
      expect(QuizJson.tryDecode({'questions': <Object?>[]}), isNull);
      expect(QuizJson.tryDecode('nada'), isNull);
      expect(
        () => QuizJson.parse({'questions': 3}),
        throwsA(isA<FormatException>()),
      );
      expect(QuizJson.decode(null).isEmpty, isTrue);
    });
  });

  test('ida y vuelta: lo guardado se lee igual', () {
    final quiz = QuizJson.tryDecode({
      'title': 'Q',
      'illustration_failure': ImageFailure.noCredits.name,
      'illustration_account': 'Trabajo',
      'questions': [
        {
          'type': 'multiple',
          'question': '¿A?',
          'options': [
            {'text': 'x', 'correct': true, 'explanation': 'e1'},
            {'text': 'y', 'correct': true},
            {'text': 'z', 'correct': false, 'explanation': 'e3'},
          ],
          'explanation': 'general',
          'hint': 'pista',
          'document_id': 'doc',
          'icon': 'book',
          'illustration_prompt': 'p',
        },
        {
          'type': 'fill_blank',
          'question': 'El ___ va.',
          'answer': 'x',
          'alternatives': ['y'],
        },
      ],
    })!;

    final again = QuizJson.decode(jsonDecode(QuizJson.encodeString(quiz)));

    expect(again, quiz);
    expect(again.hashCode, quiz.hashCode);
    expect(again.illustrationFailure, ImageFailure.noCredits);
    expect(again.illustrationAccount, 'Trabajo');
  });

  test(
    'mezclar las opciones es estable: el mismo orden con la misma semilla',
    () {
      const options = [
        QuizOption(text: 'a', correct: true),
        QuizOption(text: 'b', correct: false),
        QuizOption(text: 'c', correct: false),
        QuizOption(text: 'd', correct: false),
      ];
      expect(shuffleQuizOptions(options, 3), shuffleQuizOptions(options, 3));
      expect(shuffleQuizOptions(options, 3).toSet(), options.toSet());
    },
  );

  group('las opciones de la hoja', () {
    test('los tipos elegidos, en el orden de la hoja; ninguno válido, opción '
        'única', () {
      expect(
        quizQuestionTypes({
          CreationOptionValues.questionTypes: [
            CreationOptionValues.shortAnswer,
            'otro',
            CreationOptionValues.single,
          ],
        }),
        [QuizQuestionType.single, QuizQuestionType.shortAnswer],
      );
      expect(quizQuestionTypes(const {}), [QuizQuestionType.single]);
    });

    test('número y lo que escribe la IA crecen con «Más»', () {
      int tokens(String count) =>
          quizExpectedOutputTokens({CreationOptionValues.count: count});
      expect(quizQuestionCount({CreationOptionValues.count: 'fewer'}), 6);
      expect(quizQuestionCount(const {}), 12);
      expect(quizQuestionCount({CreationOptionValues.count: 'more'}), 20);
      expect(tokens('fewer'), lessThan(tokens('standard')));
      expect(tokens('standard'), lessThan(tokens('more')));
    });

    test('la tarea mezcla los tipos pedidos y el esquema trae solo lo que '
        'hace falta', () {
      final task = quizTask(
        count: 8,
        types: const [QuizQuestionType.single, QuizQuestionType.fillBlank],
        difficulty: CreationOptionValues.easy,
        illustrated: false,
        severalSources: false,
        topic: '',
        part: false,
        illustrations: 0,
      );
      expect(task, contains('cuestionario de 8 preguntas'));
      expect(task, contains('"opcion_unica"'));
      expect(task, contains('"completar"'));
      expect(task, isNot(contains('"respuesta_breve"')));
      expect(task, contains('explicacion'));

      final schema = quizSchema(
        types: const [QuizQuestionType.shortAnswer],
        illustrated: false,
        severalSources: false,
      );
      expect(schema, isNot(contains('opciones')));
      expect(schema, contains('respuesta'));
    });
  });
}
