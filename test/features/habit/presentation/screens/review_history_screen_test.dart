import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/habit/presentation/screens/review_history_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La pantalla del historial de repasos (F17, D8/commit 10b).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    counter = 0;
  });

  DateTime today() => harness.container.read(clockProvider)();

  Future<String> seedCard({String front = 'p'}) async {
    final itemId = 'item-${counter++}';
    final cardId = 'tarjeta-${counter++}';
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: 'Nota $itemId',
            kind: ItemKind.note,
            state: ItemState.captured,
            createdAt: today(),
            updatedAt: today(),
            deviceId: 'dispositivo',
          ),
        );
    await db
        .into(db.flashcards)
        .insert(
          FlashcardsCompanion.insert(
            id: cardId,
            itemId: itemId,
            front: front,
            back: 'r',
            dueAt: today(),
            createdAt: today(),
          ),
        );
    return cardId;
  }

  Future<void> addReview(String cardId, String grade) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: 'rev-${counter++}',
          flashcardId: cardId,
          reviewedAt: today(),
          grade: grade,
          quality: grade == 'again' ? 0 : 4,
          intervalBefore: 1,
          intervalAfter: 3,
          easeBefore: 2.5,
          easeAfter: 2.5,
          deviceId: 'dispositivo',
        ),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const ReviewHistoryScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('sin repasos, la curva y las difíciles avisan que no hay '
      'nada; el calendario igual aparece', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.reviewHistoryTitle), findsOneWidget);
    expect(find.text(es.reviewHistoryRetentionEmpty), findsOneWidget);
    expect(
      find.byKey(const Key('review-history-retention-chart')),
      findsNothing,
    );
    expect(find.text(es.reviewHistoryHardestCardsEmpty), findsOneWidget);
    expect(
      find.byKey(const Key('review-history-activity-calendar')),
      findsOneWidget,
    );
  });

  testWidgets('con un repaso hoy, la curva de retención aparece', (
    tester,
  ) async {
    final card = await seedCard();
    await addReview(card, 'good');

    await pumpScreen(tester);

    expect(
      find.byKey(const Key('review-history-retention-chart')),
      findsOneWidget,
    );
    expect(find.text(es.reviewHistoryRetentionEmpty), findsNothing);
  });

  testWidgets('una tarjeta que llega al piso aparece entre las difíciles, '
      'con su proporción de "de nuevo"', (tester) async {
    final card = await seedCard(front: '¿La más difícil?');
    await addReview(card, 'again');
    await addReview(card, 'again');
    await addReview(card, 'good');

    await pumpScreen(tester);

    expect(find.byKey(Key('hardest-card-$card')), findsOneWidget);
    expect(find.text('¿La más difícil?'), findsOneWidget);
    expect(
      find.text(es.reviewHistoryHardestCardsAgainRatio(67)),
      findsOneWidget,
    );
    expect(find.text(es.reviewHistoryHardestCardsEmpty), findsNothing);
  });

  testWidgets('se abre con el router real', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.reviewHistory);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewHistoryScreen), findsOneWidget);
  });
}
