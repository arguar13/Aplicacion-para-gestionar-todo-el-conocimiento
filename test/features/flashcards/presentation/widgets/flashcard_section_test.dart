import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/flashcard_option_draft.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/flashcard_section.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// Las tarjetas de un elemento (F27): todas se editan, y las que hizo la IA
/// llevan la marca ✨ y se les puede decir que «no era», con «Deshacer».
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late KnowledgeItem item;

  setUp(() async {
    harness = await LibraryHarness.create();
    await insertItemRows(harness.database, id: 'a', title: 'Termodinámica');
    item =
        (await harness.container.read(libraryRepositoryProvider).findById('a'))
            .getOrElse((f) => fail('$f'))!;
  });

  AppDatabase db() => harness.database;

  Future<void> seedCard({
    bool byAi = false,
    bool multipleChoice = false,
  }) async {
    AiProvenance? ai;
    if (byAi) {
      final run = await harness.container
          .read(aiRunRepositoryProvider)
          .startRun('a');
      ai = AiProvenance(runId: run.getOrElse((f) => fail('$f')));
    }
    final repository = harness.container.read(flashcardRepositoryProvider);
    final created = multipleChoice
        ? await repository.createMultipleChoice(
            itemId: 'a',
            front: '¿Qué mide?',
            options: const [
              FlashcardOptionDraft(content: 'El desorden', isCorrect: true),
              FlashcardOptionDraft(content: 'El orden', isCorrect: false),
            ],
            ai: ai,
          )
        : await repository.create(
            itemId: 'a',
            front: '¿Qué es la entropía?',
            back: 'El desorden.',
            ai: ai,
          );
    expect(created.isRight(), isTrue, reason: '$created');
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(child: FlashcardSection(item: item)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('una de la IA lleva la marca; una de la persona, no', (
    tester,
  ) async {
    await seedCard(byAi: true);
    await pumpSection(tester);
    expect(find.byTooltip(es.flashcardMadeByAi), findsOneWidget);

    await db().delete(db().flashcards).go();
    await seedCard();
    await pumpSection(tester);
    expect(find.byTooltip(es.flashcardMadeByAi), findsNothing);
  });

  testWidgets('editarla abre su pregunta y su respuesta, y al guardar deja de '
      'ser de la IA', (tester) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await tester.tap(find.byTooltip(es.flashcardsEditAction));
    await tester.pumpAndSettle();

    expect(find.text(es.flashcardsEditAction), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '¿Qué es la entropía?'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'El desorden.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '¿Qué es la entropía?'),
      '¿Qué mide la entropía?',
    );
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    final row = await db().select(db().flashcards).getSingle();
    expect(row.front, '¿Qué mide la entropía?');
    expect(row.back, 'El desorden.');
    expect(row.origin, ContentOrigin.user);
    expect(row.aiRunId, isNull);
    expect(find.byTooltip(es.flashcardMadeByAi), findsNothing);
  });

  testWidgets('cancelar la edición no cambia nada', (tester) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await tester.tap(find.byTooltip(es.flashcardsEditAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(
      (await db().select(db().flashcards).getSingle()).origin,
      ContentOrigin.ai,
    );
  });

  testWidgets('«No era» la borra, avisa, y «Deshacer» la devuelve', (
    tester,
  ) async {
    await seedCard(byAi: true);
    await pumpSection(tester);

    await openMenu(tester);
    await tester.tap(find.text(es.aiNotRight));
    await tester.pumpAndSettle();

    expect(find.text(es.flashcardRejected), findsOneWidget);
    expect(await db().select(db().flashcards).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), hasLength(1));

    await tester.tap(find.text(es.aiRejectionUndo));
    await tester.pumpAndSettle();

    expect(
      (await db().select(db().flashcards).getSingle()).origin,
      ContentOrigin.ai,
    );
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('a una de la persona solo se la borra', (tester) async {
    await seedCard();
    await pumpSection(tester);

    await openMenu(tester);
    expect(find.text(es.aiNotRight), findsNothing);
    await tester.tap(find.text(es.flashcardsDeleteAction));
    await tester.pumpAndSettle();

    expect(await db().select(db().flashcards).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('una de opción múltiple no se edita acá', (tester) async {
    await seedCard(byAi: true, multipleChoice: true);
    await pumpSection(tester);

    expect(find.byTooltip(es.flashcardsEditAction), findsNothing);
    expect(find.byTooltip(es.flashcardMadeByAi), findsOneWidget);
  });
}
