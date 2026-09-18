import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/features/relations/presentation/screens/embedding_backfill_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  final now = DateTime(2026, 9, 18, 10);

  Future<void> pumpScreen(WidgetTester tester) async {
    harness = await LibraryHarness.create(now: now);

    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.pushTo(RoutePaths.embeddingBackfill);
    await tester.pumpAndSettle();
  }

  Future<void> seedItemWithChunk(String itemId) async {
    final db = harness.database;
    await db
        .into(db.knowledgeEntries)
        .insert(
          KnowledgeEntriesCompanion.insert(
            id: itemId,
            title: 'Elemento $itemId',
            kind: ItemKind.source,
            state: ItemState.processed,
            createdAt: now,
            updatedAt: now,
            deviceId: 'test',
          ),
        );
    await db
        .into(db.chunks)
        .insert(
          ChunksCompanion.insert(
            id: '$itemId-chunk-0',
            itemId: itemId,
            seq: 0,
            content: 'Contenido de $itemId',
            charStart: 0,
            charEnd: 10,
          ),
        );
  }

  testWidgets('sin nada que revisar, lo dice al terminar', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text(es.embeddingBackfillStartAction));
    await tester.pumpAndSettle();

    expect(find.byType(EmbeddingBackfillScreen), findsOneWidget);
    expect(find.text(es.embeddingBackfillNothingToDo), findsOneWidget);
  });

  testWidgets('con fuentes por revisar, termina con el conteo indexado', (
    tester,
  ) async {
    await pumpScreen(tester);
    await seedItemWithChunk('item-1');
    await seedItemWithChunk('item-2');

    await tester.tap(find.text(es.embeddingBackfillStartAction));
    await tester.pumpAndSettle();

    expect(find.text(es.embeddingBackfillDone(2)), findsOneWidget);
  });
}
