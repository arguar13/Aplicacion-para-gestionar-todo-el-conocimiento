import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/ai_run_scope.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_review_scope.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_queue_providers.dart';
import 'package:sinapsis/features/ai_organize/presentation/screens/ai_activity_screen.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_ai_organize_queue.dart';
import '../../../../support/fake_ai_review_queue.dart';
import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';
import '../fake_ai_run_repository.dart';

/// La línea «La IA organizó esto» en el panel de la fuente del detalle (F27).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late FakeAiRunRepository runs;
  late FakeAiOrganizeQueue queue;
  late FakeAiReviewQueue reviews;

  const line = Key('ai-organized-line');

  Future<void> setUpWith(List<AiRun> initial) async {
    runs = FakeAiRunRepository(initial);
    queue = FakeAiOrganizeQueue();
    reviews = FakeAiReviewQueue();
    harness = await LibraryHarness.create(
      extraOverrides: [
        aiRunRepositoryProvider.overrideWithValue(runs),
        aiOrganizeQueueProvider.overrideWithValue(queue),
        aiReviewQueueProvider.overrideWithValue(reviews),
        aiReviewerNameProvider.overrideWithValue('gemini-3.8-flash'),
        languageModelTextBudgetProvider.overrideWithValue(
          () => kSmallWindowTextBudget,
        ),
      ],
    );
    await insertItemRows(harness.database, id: 'a', title: 'Roma');
    await insertItemRows(harness.database, id: 'b', title: 'Cartago');
  }

  Future<void> pumpDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const ItemDetailScreen(itemId: 'a')));
    await tester.pumpAndSettle();
  }

  Future<Suggestion> suggestRelation() async {
    final created = await harness.container
        .read(suggestionRepositoryProvider)
        .createRelationSuggestion(
          targetItemId: 'a',
          relatedItemId: 'b',
          relatedItemTitle: 'Cartago',
          kind: RelationKind.relatedTo,
          reason: 'La misma guerra',
        );
    return created.getOrElse((f) => fail('$f'));
  }

  testWidgets('si la IA no hizo nada, no aparece', (tester) async {
    await setUpWith(const []);
    await pumpDetail(tester);

    expect(find.byKey(line), findsNothing);
    expect(find.text(es.aiItemLineTitle), findsNothing);
  });

  testWidgets('cuenta lo que sigue en pie, sumando las pasadas', (
    tester,
  ) async {
    await setUpWith([
      fakeRun(
        'r2',
        itemId: 'a',
        remaining: const AiRunTally(relations: 3, properties: 3),
      ),
      fakeRun('r1', itemId: 'a', remaining: const AiRunTally(relations: 1)),
      // Una deshecha no cuenta, aunque haya creado algo.
      fakeRun('r0', itemId: 'a', undone: true),
    ]);
    await pumpDetail(tester);

    expect(find.byKey(line), findsOneWidget);
    expect(find.text(es.aiItemLineTitle), findsOneWidget);
    expect(find.text('4 vínculos · 3 etiquetas y propiedades'), findsOneWidget);
    expect(runs.pages.first.itemId, 'a');
  });

  testWidgets('cuenta también el tema y los datos de la '
      'referencia', (tester) async {
    await setUpWith([
      fakeRun(
        'r1',
        itemId: 'a',
        remaining: const AiRunTally(spaces: 1, referenceFields: 2),
      ),
    ]);
    await pumpDetail(tester);

    expect(find.text('1 tema · 2 datos de la referencia'), findsOneWidget);
  });

  testWidgets('si todo lo de la IA ya se adoptó o se borró, no aparece', (
    tester,
  ) async {
    await setUpWith([
      fakeRun(
        'r1',
        itemId: 'a',
        remaining: const AiRunTally(),
        created: const AiRunTally(relations: 2),
      ),
    ]);
    await pumpDetail(tester);

    expect(find.byKey(line), findsNothing);
  });

  testWidgets('con dudas pendientes, dice cuántas hay para revisar', (
    tester,
  ) async {
    await setUpWith(const []);
    await suggestRelation();
    await pumpDetail(tester);

    expect(find.byKey(line), findsOneWidget);
    expect(find.text(es.aiItemLineReviewOnly), findsOneWidget);
    expect(find.text(es.aiReviewPendingCount(1)), findsOneWidget);
    // Sin nada de la IA en pie, no hay qué deshacer.
    expect(find.byKey(const Key('ai-organized-line-undo-all')), findsNothing);
  });

  testWidgets(
    '«Deshacer todo» pregunta, deshace el elemento y la línea ofrece volver '
    'a organizarlo',
    (tester) async {
      await setUpWith([fakeRun('r1', itemId: 'a')]);
      await pumpDetail(tester);

      await tester.tap(find.byKey(const Key('ai-organized-line-undo-all')));
      await tester.pumpAndSettle();
      expect(find.text(es.aiUndoItemTitle), findsOneWidget);
      expect(
        find.text(es.aiUndoMessage('Roma', '2 vínculos · 1 tarjeta')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai-undo-confirm')));
      await tester.pumpAndSettle();

      expect(runs.undoneItems, ['a']);
      expect(
        find.text(es.aiUndoDone('2 vínculos · 1 tarjeta')),
        findsOneWidget,
      );
      // Ya no queda nada de la IA que contar ni deshacer; queda decir que la
      // IA no lo vuelve a tocar sola, y cómo pedírselo.
      expect(find.byKey(line), findsOneWidget);
      expect(find.text(es.aiItemLineUndoneTitle), findsOneWidget);
      expect(find.text(es.aiItemLineUndoneMessage), findsOneWidget);
      expect(find.byKey(const Key('ai-organized-line-undo-all')), findsNothing);
      expect(
        find.byKey(const Key('ai-organized-line-reorganize')),
        findsOneWidget,
      );
    },
  );

  testWidgets('«Volver a organizar» se lo pide a la IA y avisa', (
    tester,
  ) async {
    await setUpWith([fakeRun('r1', itemId: 'a', undone: true)]);
    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('ai-organized-line-reorganize')));
    await tester.pumpAndSettle();

    expect(queue.organizeNowCalls, ['a']);
    // Los modelos de la prueba no están bajados: lo dice en vez de prometer.
    expect(find.text(es.aiOrganizeNowNeedsModel), findsOneWidget);
  });

  testWidgets('si después de deshacer se volvió a organizar, no lo ofrece', (
    tester,
  ) async {
    await setUpWith([
      fakeRun('r2', itemId: 'a'),
      fakeRun('r1', itemId: 'a', undone: true),
    ]);
    await pumpDetail(tester);

    expect(find.text(es.aiItemLineTitle), findsOneWidget);
    expect(find.byKey(const Key('ai-organized-line-reorganize')), findsNothing);
  });

  testWidgets('analizar para estudiar después de deshacer no es volver a '
      'organizar: sigue ofreciendo «Volver a organizar» (F39)', (tester) async {
    await setUpWith([
      fakeRun(
        'estudio',
        itemId: 'a',
        scope: AiRunScope.study,
        remaining: const AiRunTally(),
        outputTokens: 100,
      ),
      fakeRun('r1', itemId: 'a', undone: true),
    ]);
    await pumpDetail(tester);

    expect(
      find.byKey(const Key('ai-organized-line-reorganize')),
      findsOneWidget,
    );
  });

  testWidgets('si se deshizo solo la última pasada, sigue contando lo de '
      'antes y ofrece las dos cosas', (tester) async {
    await setUpWith([
      fakeRun('r2', itemId: 'a', undone: true),
      fakeRun('r1', itemId: 'a', remaining: const AiRunTally(properties: 2)),
    ]);
    await pumpDetail(tester);

    expect(find.text(es.aiItemLineTitle), findsOneWidget);
    expect(find.text(es.aiTallyProperties(2)), findsOneWidget);
    expect(find.byKey(const Key('ai-organized-line-undo-all')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-organized-line-reorganize')),
      findsOneWidget,
    );
  });

  testWidgets('cancelar no deshace nada', (tester) async {
    await setUpWith([fakeRun('r1', itemId: 'a')]);
    await pumpDetail(tester);

    await tester.tap(find.byKey(const Key('ai-organized-line-undo-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.commonCancel));
    await tester.pumpAndSettle();

    expect(runs.undoneItems, isEmpty);
    expect(find.byKey(line), findsOneWidget);
  });

  testWidgets('«Ver» abre lo que hizo la IA en ese elemento, con el router '
      'real', (tester) async {
    await setUpWith([fakeRun('r1', itemId: 'a', itemTitle: 'Roma')]);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.goTo(RoutePaths.itemDetail('a'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-organized-line-see')));
    await tester.pumpAndSettle();

    final screen = tester.widget<AiActivityScreen>(
      find.byType(AiActivityScreen),
    );
    expect(screen.itemId, 'a');
    expect(find.byKey(const Key('ai-activity-item-a')), findsOneWidget);
  });

  group('revisar con otro modelo (F33)', () {
    const recheck = Key('ai-organized-line-recheck');

    testWidgets('sin tarjetas, ofrece revisar lo demás: los vínculos', (
      tester,
    ) async {
      await setUpWith([
        fakeRun('r1', itemId: 'a', remaining: const AiRunTally(relations: 2)),
      ]);
      await pumpDetail(tester);

      expect(find.byKey(recheck), findsOneWidget);
    });

    testWidgets('lo que ubicó en el árbol o ya corrigió una revisión no se '
        'revisa: no lo ofrece', (tester) async {
      await setUpWith([
        fakeRun(
          'r1',
          itemId: 'a',
          remaining: const AiRunTally(topicPlacements: 1, corrections: 2),
        ),
      ]);
      await pumpDetail(tester);

      expect(find.byKey(line), findsOneWidget);
      expect(find.byKey(recheck), findsNothing);
    });

    testWidgets('con tarjetas de la IA, ofrece revisarlas con el modelo '
        'elegido', (tester) async {
      await setUpWith([
        fakeRun('r1', itemId: 'a', remaining: const AiRunTally(flashcards: 3)),
      ]);
      await pumpDetail(tester);

      expect(find.byKey(recheck), findsOneWidget);
      expect(find.text(es.aiRecheckWith('Gemini 3.8 Flash')), findsOneWidget);
    });

    testWidgets('revisa todo lo del elemento, aunque sea del mismo modelo, '
        'después de decir cuánto cuesta', (tester) async {
      await setUpWith([
        fakeRun('r1', itemId: 'a', remaining: const AiRunTally(flashcards: 3)),
      ]);
      runs.candidates = const [AiReviewCandidate(itemId: 'a', cards: 3)];
      await pumpDetail(tester);

      await tester.tap(find.byKey(recheck));
      await tester.pumpAndSettle();
      expect(runs.candidateQueries.single, (
        reviewer: 'gemini-3.8-flash',
        madeBy: null,
        itemId: 'a',
      ));
      expect(
        find.text(
          es.aiRecheckCostScope(es.aiRecheckThings(3), es.aiRecheckItems(1), 1),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai-review-cost-start')));
      await tester.pumpAndSettle();

      expect(reviews.requests.single.itemIds, ['a']);
      expect(reviews.requests.single.skipOwnWork, isFalse);
      expect(find.text(es.aiRecheckQueued('Gemini 3.8 Flash')), findsOneWidget);
    });

    testWidgets('si no queda nada para revisar, lo dice', (tester) async {
      await setUpWith([
        fakeRun('r1', itemId: 'a', remaining: const AiRunTally(flashcards: 3)),
      ]);
      await pumpDetail(tester);

      await tester.tap(find.byKey(recheck));
      await tester.pumpAndSettle();

      expect(find.text(es.aiRecheckNothing), findsOneWidget);
      expect(reviews.requests, isEmpty);
    });
  });
}
