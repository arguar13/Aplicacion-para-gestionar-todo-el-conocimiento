import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_queue.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_generator.dart';

import '../creations_harness.dart';
import '../flashcards/support/study_fakes.dart';

/// Una respuesta de la IA con una pregunta de cada tipo; la correcta,
/// siempre primero —como suelen hacer—.
String quizReply({bool illustrated = false}) => jsonEncode({
  'titulo': 'Éxodo en preguntas',
  'preguntas': [
    for (var i = 1; i <= 3; i++)
      {
        'tipo': 'opcion_unica',
        'pregunta': '¿Pregunta $i?',
        'opciones': [
          {'texto': 'Correcta $i', 'correcta': true, 'explicacion': 'Sí.'},
          {'texto': 'Otra $i', 'correcta': false, 'explicacion': 'No.'},
          {'texto': 'Tercera $i', 'correcta': false, 'explicacion': 'No.'},
          {'texto': 'Cuarta $i', 'correcta': false, 'explicacion': 'No.'},
        ],
        if (illustrated) 'ilustracion': 'A drawing $i',
      },
    {'tipo': 'completar', 'pregunta': 'El mar se ___.', 'respuesta': 'abre'},
    {
      'tipo': 'respuesta_breve',
      'pregunta': '¿Por qué?',
      'respuesta': 'Porque sí.',
    },
  ],
});

void main() {
  late CreationsHarness h;
  late String exodo;
  late FakeModelWriter writer;
  late FakeIllustrator illustrator;
  late List<CreationQueue> queues;

  setUp(() async {
    h = await CreationsHarness.create();
    exodo = await h.processedDoc('exodo', title: 'Éxodo');
    writer = FakeModelWriter(inOrder([quizReply()]));
    illustrator = FakeIllustrator();
    queues = [];
  });
  tearDown(() async {
    for (final queue in queues) {
      queue.dispose();
    }
    await h.close();
  });

  Future<StudyCreation> generate(Map<String, Object?> options) async {
    final queue = CreationQueue(
      repository: () => h.creations,
      scopes: () => h.scopes,
      material: () => h.material,
      generators: () => {
        StudyCreationKind.quiz: QuizGenerator(
          illustrator: () => illustrator.asIllustrator,
        ),
      },
      personWriter: () => writer,
      backgroundWriter: () => writer,
    );
    queues.add(queue);
    final created = (await queue.create(
      CreationRequest(
        kind: StudyCreationKind.quiz,
        scope: CreationScope.document(exodo),
        sourceIds: [exodo],
        options: options,
      ),
    )).getRight().toNullable()!;
    for (var i = 0; i < 400; i++) {
      final creation = (await h.creations.find(
        created.id,
      )).getRight().toNullable()!;
      if (!creation.status.isPending) return creation;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw StateError('sigue pendiente');
  }

  test('create → lista: con los tipos elegidos, la dificultad y las opciones '
      'ya mezcladas —la correcta no siempre es la A—', () async {
    final done = await generate({
      CreationOptionValues.questionTypes: [
        CreationOptionValues.single,
        CreationOptionValues.fillBlank,
        CreationOptionValues.shortAnswer,
      ],
      CreationOptionValues.difficulty: CreationOptionValues.easy,
    });

    expect(done.status, CreationStatus.ready);
    expect(done.title, 'Éxodo en preguntas');
    final request = writer.requests.single;
    expect(request.task, contains('cuestionario de 12 preguntas'));
    expect(request.task, contains('recién empieza'));
    expect(request.task, contains('"completar"'));
    expect(request.task, isNot(contains('"seleccion_multiple"')));

    final quiz = QuizJson.decode(done.decodedContent);
    expect(quiz.questions.map((q) => q.id), ['q1', 'q2', 'q3', 'q4', 'q5']);
    final correctAt = [
      for (final q in quiz.questions.take(3)) q.correctIndexes.single,
    ];
    expect(correctAt.any((i) => i != 0), isTrue);
    // Mezcladas, pero con su explicación.
    final first = quiz.questions.first;
    expect(first.options[first.correctIndexes.single].text, 'Correcta 1');
    expect(first.options[first.correctIndexes.single].explanation, 'Sí.');
  });

  test('solo los tipos pedidos: una de otro tipo no entra; si ninguna es, se '
      'pide corregir', () async {
    final onlyShort = jsonEncode({
      'preguntas': [
        {'tipo': 'respuesta_breve', 'pregunta': '¿Por qué?', 'respuesta': 'x'},
      ],
    });
    writer.reply = inOrder([onlyShort, quizReply()]);

    final done = await generate({
      CreationOptionValues.questionTypes: [CreationOptionValues.single],
    });

    expect(writer.calls, hasLength(2));
    expect(writer.calls.last.lead, contains('tipos pedidos'));
    final quiz = QuizJson.decode(done.decodedContent);
    expect(quiz.questions.map((q) => q.type).toSet(), {
      QuizQuestionType.single,
    });
  });

  test('con «Incluir imágenes», hasta el tope y nunca hace fallar el '
      'cuestionario', () async {
    illustrator = FakeIllustrator(
      failure: ImageFailure.rateLimited,
      failFrom: 1,
    );
    writer.reply = inOrder([quizReply(illustrated: true)]);

    final done = await generate({CreationOptionValues.images: true});

    expect(done.status, CreationStatus.ready);
    final quiz = QuizJson.decode(done.decodedContent);
    expect(quiz.questions.first.illustrationRef, isNotNull);
    expect(quiz.questions[1].illustrationRef, isNull);
    expect(quiz.illustrationFailure, ImageFailure.rateLimited);
    expect(illustrator.prompts, hasLength(2));
  });
}
