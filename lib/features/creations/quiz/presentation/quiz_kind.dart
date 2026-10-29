import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/flashcards_kind.dart';
import 'package:sinapsis/features/creations/flashcards/presentation/widgets/study_viewer_parts.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_answer_grader.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_generator.dart';
import 'package:sinapsis/features/creations/quiz/domain/quiz_prompt.dart';
import 'package:sinapsis/features/creations/quiz/presentation/export/quiz_export.dart';
import 'package:sinapsis/features/creations/quiz/presentation/widgets/quiz_viewer.dart';

/// Quien revisa las respuestas breves con la IA elegida, con el turno de la
/// persona: es ella la que espera la respuesta.
final quizAnswerGraderProvider = Provider<QuizAnswerGrader>(
  (ref) => QuizAnswerGrader(
    writer: () => ref.read(structuredWriterProvider),
    readiness: () => ref.read(languageModelStatusCheckProvider),
  ),
);

/// El generador del «Cuestionario» (F43, paso 8): su línea en
/// `creationGeneratorsProvider`.
final quizGeneratorProvider = Provider<CreationGenerator>(
  (ref) => QuizGenerator(illustrator: () => ref.read(studyIllustratorProvider)),
);

/// Cómo es el «Cuestionario» en Repasar (F43, paso 8): su línea en
/// `creationKindSpecsProvider`. Las opciones de fábrica del plan —número,
/// dificultad, «Incluir imágenes» (con IA), los cuatro tipos de pregunta,
/// idioma, fuentes y tema—, su visor, su botón de descargar y su archivo.
final quizKindSpecProvider = Provider<CreationKindSpec>((ref) {
  final base = defaultCreationKindSpec(StudyCreationKind.quiz);
  return base.copyWith(
    options: withIllustratedImages(
      base.options,
      hint: (l) => l.f43QuizOptImagesHint,
    ),
    expectedOutputTokens: quizExpectedOutputTokens,
    illustrations: quizIllustrationCount,
    viewerBuilder: (context, creation) =>
        QuizViewer(key: ValueKey(creation.id), creation: creation),
    viewerActions: (context, creation) => [
      StudyDownloadButton(creation: creation),
    ],
    exporter: exportQuiz,
  );
});
