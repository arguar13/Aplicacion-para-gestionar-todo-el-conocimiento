import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/flashcards/domain/item_illustrations.dart';
import 'package:sinapsis/features/creations/flashcards/domain/study_items.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_prompt.dart';

/// Genera un «Cuestionario» (F43, paso 8): las preguntas de los tipos
/// elegidos —opción única, selección múltiple, completar espacios, respuesta
/// breve—, con la explicación de cada opción, de una vez o por partes
/// ([writeStudyItems]), y, si se pidió, unas pocas ilustraciones con IA que
/// nunca hacen fallar el cuestionario.
///
/// Las opciones se guardan ya mezcladas —la IA tiende a poner la correcta
/// primero— y siempre en el mismo orden: «la C» es la C cada vez que se abre.
class QuizGenerator extends CreationGenerator {
  const QuizGenerator({required StudyIllustrator Function() illustrator})
    : _illustrator = illustrator;

  final StudyIllustrator Function() _illustrator;

  @override
  StudyCreationKind get kind => StudyCreationKind.quiz;

  @override
  int maxOutputTokens(CreationJob job) => quizExpectedOutputTokens(job.options);

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: studyItemsReplyTokens(
          _request(job, severalSources: true),
          contextTokens,
        ),
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final illustrated = job.options[CreationOptionValues.images] == true;
    final batch = await writeStudyItems(
      request: _request(job, severalSources: material.sources.length > 1),
      job: job,
      material: material,
      writer: writer,
      progress: progress,
      share: illustrated ? 0.7 : 1,
    );
    var quiz = Quiz(
      title: batch.title,
      questions: [
        for (final (index, question) in batch.items.indexed)
          question.copyWith(
            id: 'q${index + 1}',
            options: shuffleQuizOptions(question.options, index * 7919 + 17),
          ),
      ],
    );
    if (illustrated) quiz = await _illustrate(quiz, job, progress);
    if (job.cancellation.isCancelled) throw const CreationCancelledException();
    return CreationOutput(
      title: quiz.title,
      content: QuizJson.encodeString(quiz),
    );
  }

  StudyItemsRequest<QuizQuestion> _request(
    CreationJob job, {
    required bool severalSources,
  }) {
    final options = job.options;
    final types = quizQuestionTypes(options);
    final illustrated = options[CreationOptionValues.images] == true;
    final topic = '${options[CreationOptionKeys.topic] ?? ''}';
    return StudyItemsRequest(
      count: quizQuestionCount(options),
      tokensPerItem: quizTokensPerQuestion(options),
      task: (count, {required part}) => quizTask(
        count: count,
        types: types,
        difficulty: options[CreationOptionValues.difficulty],
        illustrated: illustrated,
        severalSources: severalSources && !part,
        topic: topic,
        part: part,
        illustrations: quizIllustrationCount(options),
      ),
      schema: quizSchema(
        types: types,
        illustrated: illustrated,
        severalSources: severalSources,
      ),
      parse: (json) {
        final quiz = QuizJson.parse(json);
        // Solo los tipos elegidos: una de otro tipo no es lo que se pidió.
        final wanted = [
          for (final question in quiz.questions)
            if (types.contains(question.type)) question,
        ];
        if (wanted.isEmpty) {
          throw FormatException(
            'Ninguna pregunta es de los tipos pedidos '
            '(${types.map((t) => t.storageKey).join(', ')}).',
          );
        }
        return StudyItemBatch(title: quiz.title, items: wanted);
      },
    );
  }

  Future<Quiz> _illustrate(
    Quiz quiz,
    CreationJob job,
    CreationProgressReport progress,
  ) async {
    final wanted = [
      for (final question in quiz.questions)
        if (question.illustrationPrompt.isNotEmpty)
          (question.id, question.illustrationPrompt),
    ].take(quizIllustrationCount(job.options)).toList();
    if (wanted.isEmpty) return quiz;
    final accountId = job.options[CreationOptionKeys.imageAccountId];
    final drawn = await _illustrator()(
      creationId: job.creation.id,
      wanted: wanted,
      cancellation: job.cancellation,
      accountId: accountId is String && accountId.isNotEmpty ? accountId : null,
      onDrawn: (done, total) =>
          progress(0.7 + 0.3 * done / total, CreationStep.finishing),
    );
    return Quiz(
      title: quiz.title,
      illustrationFailure: drawn.failure,
      illustrationAccount: drawn.account,
      questions: [
        for (final question in quiz.questions)
          if (drawn.references[question.id] case final reference?)
            question.copyWith(illustrationRef: reference)
          else
            question,
      ],
    );
  }
}
