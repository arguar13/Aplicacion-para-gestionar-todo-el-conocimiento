import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/quiz_session_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La sesión suelta de quiz (F20, commit 8): camina las preguntas de a una,
/// sin tocar la programación SM-2, y al terminar cuenta el puntaje + qué
/// temas del Atlas concentraron los errores.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    counter = 0;
  });

  Future<String> seedItem({String? withTema}) async {
    final n = counter++;
    final id = 'item-$n';
    final now = harness.container.read(clockProvider)();
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Elemento $n',
            source: Source(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
              url: 'https://ejemplo.org/$n',
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (withTema != null) {
      final db = harness.database;
      final definitionId = await temaDefinitionId(db);
      final temaId = 'tema-$withTema';
      final existing = await (db.select(
        db.propertyValues,
      )..where((v) => v.id.equals(temaId))).getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.propertyValues)
            .insert(
              PropertyValuesCompanion.insert(
                id: temaId,
                definitionId: definitionId,
                value: withTema,
                createdAt: now,
              ),
            );
      }
      await db
          .into(db.itemPropertyValues)
          .insert(
            ItemPropertyValuesCompanion.insert(
              itemId: id,
              propertyValueId: temaId,
            ),
          );
    }
    return id;
  }

  Future<Flashcard> seedCard({
    required String front,
    required String correct,
    required String wrong,
    String? tema,
  }) async {
    final itemId = await seedItem(withTema: tema);
    final result = await harness.container
        .read(flashcardRepositoryProvider)
        .createMultipleChoice(
          itemId: itemId,
          front: front,
          options: [
            FlashcardOptionDraft(content: correct, isCorrect: true),
            FlashcardOptionDraft(content: wrong, isCorrect: false),
          ],
        );
    return result.getRight().toNullable()!;
  }

  Future<void> pumpSession(WidgetTester tester, List<Flashcard> cards) async {
    await tester.pumpWidget(harness.wrap(QuizSessionScreen(cards: cards)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'camina las preguntas de a una y al terminar muestra el puntaje',
    (tester) async {
      final card1 = await seedCard(
        front: '¿Primera?',
        correct: 'Correcta uno',
        wrong: 'Incorrecta uno',
      );
      final card2 = await seedCard(
        front: '¿Segunda?',
        correct: 'Correcta dos',
        wrong: 'Incorrecta dos',
      );
      await pumpSession(tester, [card1, card2]);

      expect(find.text(es.quizSessionRemaining(2)), findsOneWidget);
      expect(find.text('¿Primera?'), findsOneWidget);

      await tester.tap(find.text('Correcta uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.quizSessionNext));
      await tester.pumpAndSettle();

      expect(find.text(es.quizSessionRemaining(1)), findsOneWidget);
      expect(find.text('¿Segunda?'), findsOneWidget);

      await tester.tap(find.text('Incorrecta dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.quizSessionFinish));
      await tester.pumpAndSettle();

      expect(find.text(es.quizSessionScore(1, 2)), findsOneWidget);
    },
  );

  testWidgets('terminar la sesión cuenta para la racha, sin tocar SM-2', (
    tester,
  ) async {
    final card = await seedCard(
      front: '¿Pregunta?',
      correct: 'Correcta',
      wrong: 'Incorrecta',
    );
    final before = harness.container.read(clockProvider)();
    await pumpSession(tester, [card]);

    await tester.tap(find.text('Correcta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.quizSessionFinish));
    await tester.pumpAndSettle();

    final events = await harness.database
        .select(harness.database.habitEvents)
        .get();
    expect(events.map((e) => e.kind), contains(HabitEventKind.quiz));

    final refreshed =
        (await harness.container.read(flashcardRepositoryProvider).getAll())
            .getRight()
            .toNullable()!
            .single;
    // Sigue con la misma programación de cuando se creó: la sesión suelta
    // no llamó a review().
    expect(refreshed.repetitions, 0);
    expect(refreshed.dueAt, before);
  });

  testWidgets(
    'al terminar con errores, agrupa por tema y ofrece ir a la nota viva',
    (tester) async {
      final card = await seedCard(
        front: '¿Pregunta?',
        correct: 'Correcta',
        wrong: 'Incorrecta',
        tema: 'Roma',
      );
      await pumpSession(tester, [card]);

      await tester.tap(find.text('Incorrecta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.quizSessionFinish));
      await tester.pumpAndSettle();

      expect(find.text(es.quizSessionScore(0, 1)), findsOneWidget);
      expect(find.text('Roma'), findsOneWidget);
      expect(find.text(es.quizSessionMissedCount(1)), findsOneWidget);
    },
  );
}
