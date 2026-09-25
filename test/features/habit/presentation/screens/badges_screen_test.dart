import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/habit/presentation/screens/badges_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La pantalla de insignias (F17, D7/commit 9b): las seis se muestran
/// siempre, ganadas o no.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
  });

  Future<void> seedMatureNote() async {
    const id = 'nota-madura';
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Nota madura',
            source: Source(
              id: 'origin-$id',
              kind: SourceKind.manualNote,
              capturedAt: DateTime.utc(2026, 9),
            ),
            processingState: ProcessingState.ready,
            createdAt: DateTime.utc(2026, 9),
            updatedAt: DateTime.utc(2026, 9),
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.blocks,
                content: encodeContentBlocks([
                  ContentBlock.paragraph(
                    text: 'x',
                    addedAt: DateTime.utc(2026, 9),
                  ),
                ]),
                isPrimary: true,
                createdAt: DateTime.utc(2026, 9),
              ),
            ],
          ),
        );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      const KnowledgeNotesCompanion(maturity: Value(NoteMaturity.mature)),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const BadgesScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('lista las seis insignias, ninguna ganada al empezar', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text(es.habitBadgesTitle), findsOneWidget);
    expect(find.text(es.habitBadgeFirstMatureNoteLabel), findsOneWidget);
    expect(find.text(es.habitBadgeTenLivingNotesLabel), findsOneWidget);
    expect(find.text(es.habitBadgeHundredReviewsLabel), findsOneWidget);
    expect(
      find.text(es.habitBadgeContradictionResolvedLabel),
      findsOneWidget,
    );
    expect(find.text(es.habitBadgeCompleteTopicBranchLabel), findsOneWidget);
    expect(
      find.text(es.habitBadgeMonthOfWeeklyConsolidationLabel),
      findsOneWidget,
    );
    expect(find.text(es.habitBadgeEarnedLabel), findsNothing);
  });

  testWidgets('una nota madura marca esa insignia como ganada, sola', (
    tester,
  ) async {
    await seedMatureNote();

    await pumpScreen(tester);

    expect(find.text(es.habitBadgeEarnedLabel), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('badge-firstMatureNote')),
        matching: find.text(es.habitBadgeEarnedLabel),
      ),
      findsOneWidget,
    );
  });

  testWidgets('se abre con el router real', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.reviewBadges);
    await tester.pumpAndSettle();

    expect(find.byType(BadgesScreen), findsOneWidget);
  });
}
