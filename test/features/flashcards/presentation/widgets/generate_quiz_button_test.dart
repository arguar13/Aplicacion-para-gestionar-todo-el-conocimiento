import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/flashcards/domain/services/distractor_sourcer.dart';
import 'package:sinapsis/features/flashcards/domain/usecases/generate_quiz_usecase.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/generate_quiz_button.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// Devuelve exactamente los resultados/lo que se le dé, sin tocar el modelo
/// ni la bóveda —eso ya se prueba solo en `generate_quiz_usecase_test.dart`,
/// acá lo que importa es cómo reacciona el BOTÓN y la pantalla de revisión—.
class _FakeGenerateQuizUseCase implements GenerateQuizUseCase {
  _FakeGenerateQuizUseCase({
    Either<Failure, List<QuizQuestionResult>>? generateResult,
    Either<Failure, List<Flashcard>>? saveResult,
  }) : _generateResult = generateResult ?? right(const []),
       _saveResult = saveResult ?? right(const []);

  final Either<Failure, List<QuizQuestionResult>> _generateResult;
  final Either<Failure, List<Flashcard>> _saveResult;

  KnowledgeItem? itemSeen;
  List<QuizQuestionResult>? confirmedSeen;

  @override
  Future<Either<Failure, List<QuizQuestionResult>>> generate({
    required KnowledgeItem item,
    int count = 5,
  }) async {
    itemSeen = item;
    return _generateResult;
  }

  @override
  Future<Either<Failure, List<Flashcard>>> save({
    required String itemId,
    required List<QuizQuestionResult> confirmed,
  }) async {
    confirmedSeen = confirmed;
    return _saveResult;
  }
}

KnowledgeItem _fixtureItem(String id) => KnowledgeItem(
  id: id,
  title: 'Fuente',
  source: Source(
    id: 'src-$id',
    kind: SourceKind.webPage,
    capturedAt: DateTime(2026, 9, 25),
  ),
  processingState: ProcessingState.ready,
  createdAt: DateTime(2026, 9, 25),
  updatedAt: DateTime(2026, 9, 25),
);

QuizQuestionResult _fixtureQuestion(String question) => QuizQuestionResult(
  question: question,
  correctAnswer: 'la correcta',
  correctSourceCharStart: 0,
  correctSourceCharEnd: 12,
  distractors: [
    const DistractorCandidate(
      itemId: 'other',
      content: 'un distractor',
      sourceChunkId: 'chunk-other',
      sourceCharStart: 0,
      sourceCharEnd: 13,
    ),
  ],
);

/// El botón "Generar quiz" (F20, 20.6/N): el aviso de modelo requerido, el
/// paso a la pantalla de revisión, y el guardado desde ahí.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool chatModelReady = false,
    _FakeGenerateQuizUseCase? useCase,
  }) async {
    harness = await LibraryHarness.create(
      chatModelReady: chatModelReady,
      // En el contenedor real de la harness, no en un `ProviderScope`
      // interno: `GenerateQuizButton` empuja la revisión con
      // `Navigator.push`, y esa ruta cuelga del `Overlay` del `Navigator`
      // como HERMANA de la ruta inicial, no como su descendiente —un
      // `ProviderScope(overrides: …)` alrededor de `home:` no llega ahí—.
      extraOverrides: [
        if (useCase != null)
          generateQuizUseCaseProvider.overrideWithValue(useCase),
      ],
    );
    await tester.pumpWidget(
      harness.wrap(Scaffold(body: GenerateQuizButton(item: _fixtureItem('a')))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin el modelo descargado, avisa y ofrece descargarlo', (
    tester,
  ) async {
    await pumpButton(tester);

    await tester.tap(find.byTooltip(es.quizGenerateTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.quizModelRequired), findsOneWidget);
    expect(find.text(es.derivedNoteDownloadAction), findsOneWidget);
  });

  testWidgets('sin contenido generado, avisa que no se pudo generar nada', (
    tester,
  ) async {
    final useCase = _FakeGenerateQuizUseCase(generateResult: right(const []));
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tester.tap(find.byTooltip(es.quizGenerateTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.quizGenerationFailed), findsOneWidget);
    expect(useCase.itemSeen?.id, 'a');
  });

  testWidgets('si el caso de uso falla, avisa el error', (tester) async {
    final useCase = _FakeGenerateQuizUseCase(
      generateResult: left(
        const Failure.validation(message: 'nada que generar en la prueba'),
      ),
    );
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tester.tap(find.byTooltip(es.quizGenerateTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.globalErrorValidation), findsOneWidget);
  });

  testWidgets(
    'con preguntas generadas, abre la revisión; confirmar guarda y avisa',
    (tester) async {
      final useCase = _FakeGenerateQuizUseCase(
        generateResult: right([_fixtureQuestion('¿Una pregunta?')]),
        saveResult: right([
          Flashcard(
            id: 'card-1',
            itemId: 'a',
            front: '¿Una pregunta?',
            back: 'la correcta',
            dueAt: DateTime(2026, 9, 25),
            createdAt: DateTime(2026, 9, 25),
            kind: FlashcardKind.multipleChoice,
          ),
        ]),
      );
      await pumpButton(tester, chatModelReady: true, useCase: useCase);

      await tester.tap(find.byTooltip(es.quizGenerateTooltip));
      await tester.pumpAndSettle();

      expect(find.text(es.quizReviewTitle), findsOneWidget);
      expect(find.text('¿Una pregunta?'), findsOneWidget);

      await tester.tap(find.text(es.quizReviewConfirm(1)));
      await tester.pumpAndSettle();

      expect(find.text(es.quizReviewTitle), findsNothing);
      expect(find.text(es.quizSaved(1)), findsOneWidget);
      expect(useCase.confirmedSeen, hasLength(1));
    },
  );

  testWidgets('destildar una pregunta la deja afuera de lo confirmado', (
    tester,
  ) async {
    final useCase = _FakeGenerateQuizUseCase(
      generateResult: right([
        _fixtureQuestion('¿Primera?'),
        _fixtureQuestion('¿Segunda?'),
      ]),
    );
    await pumpButton(tester, chatModelReady: true, useCase: useCase);

    await tester.tap(find.byTooltip(es.quizGenerateTooltip));
    await tester.pumpAndSettle();

    expect(find.text(es.quizReviewConfirm(2)), findsOneWidget);

    await tester.tap(find.byKey(const Key('quiz-question-1')));
    await tester.pumpAndSettle();

    expect(find.text(es.quizReviewConfirm(1)), findsOneWidget);

    await tester.tap(find.text(es.quizReviewConfirm(1)));
    await tester.pumpAndSettle();

    final confirmed = useCase.confirmedSeen!;
    expect(confirmed, hasLength(1));
    expect(confirmed.single.question, '¿Primera?');
  });
}
