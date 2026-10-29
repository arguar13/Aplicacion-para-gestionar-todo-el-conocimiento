import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_answer_grader.dart';
import 'package:sinapsis/features/creations/quiz/presentation/quiz_kind.dart';

import '../flashcards/support/study_fakes.dart';
import '../flashcards/support/study_viewer_harness.dart';

const _single = QuizQuestion(
  id: 'q1',
  type: QuizQuestionType.single,
  prompt: '¿Quién guía al pueblo?',
  options: [
    QuizOption(text: 'Aarón', correct: false, explanation: 'Lo ayuda.'),
    QuizOption(text: 'Moisés', correct: true, explanation: 'Es el que guía.'),
    QuizOption(text: 'Faraón', correct: false, explanation: 'Los persigue.'),
    QuizOption(text: 'Josué', correct: false, explanation: 'Viene después.'),
  ],
  explanation: 'Moisés guía la salida de Egipto.',
);

const _multiple = QuizQuestion(
  id: 'q2',
  type: QuizQuestionType.multiple,
  prompt: '¿Qué pasa en el camino?',
  options: [
    QuizOption(text: 'El mar se abre', correct: true),
    QuizOption(text: 'Llueve fuego', correct: false),
    QuizOption(text: 'Llegan al Sinaí', correct: true),
  ],
);

const _blank = QuizQuestion(
  id: 'q3',
  type: QuizQuestionType.fillBlank,
  prompt: 'El pueblo llega al monte $kQuizBlank.',
  answer: 'Sinaí',
  explanation: 'Ahí recibe la ley.',
);

const _blankLong = QuizQuestion(
  id: 'q5',
  type: QuizQuestionType.fillBlank,
  prompt: 'Cruzan el $kQuizBlank.',
  answer: 'Mar Mediterráneo',
);

const _short = QuizQuestion(
  id: 'q4',
  type: QuizQuestionType.shortAnswer,
  prompt: '¿Por qué salen de Egipto?',
  answer: 'Para dejar la esclavitud.',
);

String _quiz(List<QuizQuestion> questions) =>
    QuizJson.encodeString(Quiz(title: 'Éxodo', questions: questions));

void main() {
  late StudyViewerHarness h;
  late FakeModelWriter writer;
  late LanguageModelStatus status;

  setUp(() async {
    writer = FakeModelWriter(
      inOrder(['{"correcta": true, "razon": "Dice lo esencial."}']),
    );
    status = const LanguageModelReady(provider: AiProvider.gemini);
    h = await StudyViewerHarness.create(
      overrides: [
        quizAnswerGraderProvider.overrideWithValue(
          QuizAnswerGrader(
            writer: () => writer,
            readiness: () =>
                ({bool background = false}) async => status,
          ),
        ),
      ],
    );
  });

  Future<StudyCreation> quiz(List<QuizQuestion> questions) =>
      h.ready(StudyCreationKind.quiz, _quiz(questions));

  String progress(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('quiz-progress'))).data!;

  Future<void> tapKey(WidgetTester tester, String key) async {
    // Lo escrito se deja de editar antes de tocar, como al cerrar el teclado.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('opción única', () {
    testWidgets('«6 / 14» y A–D; la correcta: verde con «¡Exacto!» y la '
        'explicación de cada opción', (tester) async {
      await h.open(tester, await quiz(const [_single, _blank]));

      expect(progress(tester), '1 / 2');
      expect(find.text('Opción única'), findsOneWidget);
      for (final letter in ['A', 'B', 'C', 'D']) {
        expect(find.text(letter), findsOneWidget);
      }
      expect(find.text('Es el que guía.'), findsNothing);

      await tapKey(tester, 'quiz-option-1');

      expect(find.byKey(const Key('quiz-verdict-right')), findsOneWidget);
      expect(find.text('¡Exacto!'), findsOneWidget);
      for (final why in [
        'Lo ayuda.',
        'Es el que guía.',
        'Los persigue.',
        'Viene después.',
      ]) {
        expect(find.text(why), findsOneWidget);
      }
      expect(find.text('Moisés guía la salida de Egipto.'), findsOneWidget);
    });

    testWidgets('la equivocada: la elegida en rojo, la correcta en verde, y '
        'no se puede cambiar', (tester) async {
      await h.open(tester, await quiz(const [_single]));

      await tapKey(tester, 'quiz-option-0');

      expect(find.byKey(const Key('quiz-verdict-wrong')), findsOneWidget);
      expect(find.text('No es así'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsWidgets);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // Tocar otra después no cambia nada.
      await tapKey(tester, 'quiz-option-1');
      expect(find.byKey(const Key('quiz-verdict-wrong')), findsOneWidget);
    });
  });

  testWidgets('selección múltiple: se tildan y se comprueba', (tester) async {
    await h.open(tester, await quiz(const [_multiple]));

    expect(find.text('Elegí todas las que correspondan'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('quiz-check')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'quiz-option-0');
    await tapKey(tester, 'quiz-option-2');
    // Tildar y destildar.
    await tapKey(tester, 'quiz-option-1');
    await tapKey(tester, 'quiz-option-1');
    expect(find.byKey(const Key('quiz-verdict-right')), findsNothing);

    await tapKey(tester, 'quiz-check');
    expect(find.byKey(const Key('quiz-verdict-right')), findsOneWidget);
  });

  group('completar espacios', () {
    testWidgets('se compara sin tildes ni mayúsculas', (tester) async {
      await h.open(tester, await quiz(const [_blank]));

      await tester.enterText(
        find.byKey(const Key('quiz-typed-field')),
        'SINAI',
      );
      await tapKey(tester, 'quiz-check');

      expect(find.text('¡Exacto!'), findsOneWidget);
      expect(find.byKey(const Key('quiz-expected')), findsOneWidget);
      expect(find.text('Ahí recibe la ley.'), findsOneWidget);
    });

    testWidgets('mal escrita: no es así, con la diferencia', (tester) async {
      await h.open(tester, await quiz(const [_blank]));

      await tester.enterText(
        find.byKey(const Key('quiz-typed-field')),
        'Horeb',
      );
      await tapKey(tester, 'quiz-check');

      expect(find.byKey(const Key('quiz-verdict-wrong')), findsOneWidget);
      expect(find.byKey(const Key('quiz-comparison')), findsOneWidget);
    });

    testWidgets('un «casi» lo decide la persona', (tester) async {
      await h.open(tester, await quiz(const [_blankLong]));

      await tester.enterText(
        find.byKey(const Key('quiz-typed-field')),
        'mar mediteraneo',
      );
      await tapKey(tester, 'quiz-check');
      expect(find.text('Casi'), findsOneWidget);
      expect(find.byKey(const Key('quiz-comparison')), findsOneWidget);

      await tapKey(tester, 'quiz-self-right');
      expect(find.byKey(const Key('quiz-verdict-right')), findsOneWidget);
      expect(find.text('La diste por bien'), findsOneWidget);
    });
  });

  group('respuesta breve', () {
    testWidgets('con IA: la IA dice si está bien y por qué', (tester) async {
      await h.open(tester, await quiz(const [_short]));

      await tester.enterText(
        find.byKey(const Key('quiz-typed-field')),
        'Porque eran esclavos',
      );
      await tapKey(tester, 'quiz-check');

      expect(find.text('La IA dice que está bien'), findsOneWidget);
      expect(find.text('Dice lo esencial.'), findsOneWidget);
      expect(find.byKey(const Key('quiz-expected')), findsOneWidget);
      expect(writer.calls.single.material, contains('Porque eran esclavos'));
    });

    testWidgets('mientras revisa se ve la espera, y cancelar deja '
        'calificarla a mano', (tester) async {
      final reply = Completer<String>();
      writer.reply = (_) => reply.future;
      await h.open(tester, await quiz(const [_short]));

      await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'x');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quiz-check')));
      await tester.tap(find.byKey(const Key('quiz-check')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('quiz-grading')), findsOneWidget);
      expect(find.text('La IA está revisando tu respuesta…'), findsOneWidget);

      await tapKey(tester, 'quiz-grading-cancel');
      expect(find.byKey(const Key('quiz-grading')), findsNothing);
      expect(find.byKey(const Key('quiz-self-right')), findsOneWidget);
      expect(find.text('Para dejar la esclavitud.'), findsOneWidget);
      reply.complete('{"correcta": true}');
      await tester.pumpAndSettle();
      // Lo que llegó tarde no pisa lo que decide la persona.
      expect(find.byKey(const Key('quiz-verdict-right')), findsNothing);

      await tapKey(tester, 'quiz-self-wrong');
      expect(find.byKey(const Key('quiz-verdict-wrong')), findsOneWidget);
      expect(find.text('La diste por mal'), findsOneWidget);
    });

    testWidgets('sin IA: la respuesta esperada y uno se autocalifica', (
      tester,
    ) async {
      status = const LanguageModelNeedsDownload();
      await h.open(tester, await quiz(const [_short]));

      await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'x');
      await tapKey(tester, 'quiz-check');

      expect(find.text('Sin una IA lista: calificala vos.'), findsOneWidget);
      expect(find.text('Para dejar la esclavitud.'), findsOneWidget);
      expect(writer.calls, isEmpty);
      await tapKey(tester, 'quiz-self-right');
      expect(find.byKey(const Key('quiz-verdict-right')), findsOneWidget);
    });

    testWidgets('si la IA no puede, se autocalifica', (tester) async {
      writer.reply = inOrder(['nada']);
      await h.open(tester, await quiz(const [_short]));

      await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'x');
      await tapKey(tester, 'quiz-check');

      expect(
        find.text('La IA no pudo revisarla: calificala vos.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('quiz-self-right')), findsOneWidget);
    });
  });

  testWidgets('al final, el puntaje y «Repetir solo las que fallé» con las '
      'falladas y las salteadas', (tester) async {
    await h.open(tester, await quiz(const [_single, _multiple, _blank]));

    await tapKey(tester, 'quiz-option-1');
    await tapKey(tester, 'quiz-next');
    expect(progress(tester), '2 / 3');
    // La salteo.
    await tapKey(tester, 'quiz-next');
    await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'Egipto');
    await tapKey(tester, 'quiz-check');
    expect(find.text('Ver el resultado'), findsOneWidget);
    await tapKey(tester, 'quiz-next');

    expect(find.byKey(const Key('quiz-score')), findsOneWidget);
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('33 % bien'), findsOneWidget);

    await tapKey(tester, 'quiz-retry-missed');
    expect(find.byKey(const Key('quiz-retry-round')), findsOneWidget);
    expect(progress(tester), '1 / 2');
    expect(find.text('¿Qué pasa en el camino?'), findsOneWidget);
    await tapKey(tester, 'quiz-next');
    // Lo escrito antes no queda: es otra vuelta.
    expect(find.text('Egipto'), findsNothing);
    await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'sinai');
    await tapKey(tester, 'quiz-check');
    await tapKey(tester, 'quiz-next');
    expect(find.text('1 de 2'), findsOneWidget);

    await tapKey(tester, 'quiz-restart');
    expect(progress(tester), '1 / 3');
  });

  testWidgets('todo bien: sin «Repetir solo las que fallé»', (tester) async {
    await h.open(tester, await quiz(const [_single]));
    await tapKey(tester, 'quiz-option-1');
    await tapKey(tester, 'quiz-next');
    expect(find.text('¡Todas bien!'), findsOneWidget);
    expect(find.byKey(const Key('quiz-retry-missed')), findsNothing);
  });

  testWidgets('un cuestionario vacío lo dice', (tester) async {
    await h.open(tester, await h.ready(StudyCreationKind.quiz, '{}'));
    expect(find.byKey(const Key('quiz-viewer-empty')), findsOneWidget);
  });

  testWidgets('a 360 de ancho con la letra al doble, en oscuro, sin '
      'desbordarse —respondida y en el puntaje—', (tester) async {
    await h.open(
      tester,
      await quiz(const [_single, _short]),
      size: const Size(360, 780),
      theme: AppThemeChoice.dark,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'quiz-option-1');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'quiz-next');
    status = const LanguageModelNeedsDownload();
    await tester.enterText(find.byKey(const Key('quiz-typed-field')), 'x');
    await tapKey(tester, 'quiz-check');
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'quiz-next');
    expect(find.byKey(const Key('quiz-score')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en los nueve temas se ve sin desbordarse', (tester) async {
    final created = await quiz(const [_single]);
    for (final theme in AppThemeChoice.values) {
      await h.open(tester, created, size: const Size(360, 780), theme: theme);
      await tapKey(tester, 'quiz-option-0');
      expect(tester.takeException(), isNull, reason: theme.name);
    }
  });
}
