import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/health/presentation/screens/grown_notes_screen.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// El reloj del harness marca el 11 de septiembre de 2026 a las 10:00, así que
/// "esta semana" empieza el 4: lo que nació el 10 crece, lo del 1 no.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;

  final recent = DateTime.utc(2026, 9, 10);
  final old = DateTime.utc(2026, 9);

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
  });

  Future<void> seedNote(
    String id, {
    String? title,
    List<ContentBlock>? blocks,
    NoteKind kind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
  }) async {
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: title ?? 'Nota $id',
            source: Source(
              id: 'src-$id',
              kind: SourceKind.manualNote,
              capturedAt: recent,
            ),
            processingState: ProcessingState.ready,
            createdAt: recent,
            updatedAt: recent,
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.blocks,
                content: encodeContentBlocks(
                  blocks ??
                      [ContentBlock.paragraph(text: 'x', addedAt: recent)],
                ),
                isPrimary: true,
                createdAt: recent,
              ),
            ],
          ),
        );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
  }

  Future<void> relate(String from, String to) => db
      .into(db.relations)
      .insert(
        RelationsCompanion.insert(
          id: 'rel-$from-$to',
          fromItemId: from,
          toItemId: to,
          kind: RelationKind.relatedTo,
          createdAt: recent,
        ),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const GrownNotesScreen()),
              GoRoute(
                path: RoutePaths.itemDetailPattern,
                builder: (_, state) => Scaffold(
                  body: Text('detalle de ${state.pathParameters['id']}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista cada nota que creció, con cuánto y en qué etapa está', (
    tester,
  ) async {
    await seedNote(
      'a',
      title: 'Roma',
      maturity: NoteMaturity.developing,
      blocks: [
        ContentBlock.paragraph(text: 'uno', addedAt: recent),
        ContentBlock.paragraph(text: 'dos', addedAt: recent),
      ],
    );
    await seedNote('b', title: 'Cartago');
    await relate('a', 'b');

    await pumpScreen(tester);

    expect(find.text(es.grownNotesTitle), findsOneWidget);
    expect(find.text(es.grownNotesHint), findsOneWidget);
    expect(
      find.text(
        '${es.grownNotesNewBlocks(2)} · ${es.grownNotesNewRelations(1)}',
      ),
      findsOneWidget,
    );
    // Cartago solo ganó un bloque y un vínculo.
    expect(
      find.text(
        '${es.grownNotesNewBlocks(1)} · ${es.grownNotesNewRelations(1)}',
      ),
      findsOneWidget,
    );
    expect(find.text(es.noteMaturityDeveloping), findsOneWidget);
    expect(find.text(es.noteMaturitySeed), findsOneWidget);
  });

  testWidgets('las que más crecieron van primero', (tester) async {
    await seedNote('poco', title: 'Poco');
    await seedNote(
      'mucho',
      title: 'Mucho',
      blocks: [
        ContentBlock.paragraph(text: 'uno', addedAt: recent),
        ContentBlock.paragraph(text: 'dos', addedAt: recent),
        ContentBlock.paragraph(text: 'tres', addedAt: recent),
      ],
    );

    await pumpScreen(tester);

    final muchoY = tester.getTopLeft(find.text('Mucho')).dy;
    final pocoY = tester.getTopLeft(find.text('Poco')).dy;
    expect(muchoY, lessThan(pocoY));
  });

  testWidgets('no lista lo que no creció esta semana, ni lo que no es una '
      'nota viva', (tester) async {
    await seedNote('viva', title: 'Viva');
    await seedNote(
      'vieja',
      title: 'Vieja',
      blocks: [ContentBlock.paragraph(text: 'x', addedAt: old)],
    );
    await seedNote('atomica', title: 'Atómica', kind: NoteKind.atomic);
    await seedNote('mapa', title: 'Mapa', kind: NoteKind.map);

    await pumpScreen(tester);

    expect(find.text('Viva'), findsOneWidget);
    expect(find.text('Vieja'), findsNothing);
    expect(find.text('Atómica'), findsNothing);
    expect(find.text('Mapa'), findsNothing);
  });

  testWidgets('si ninguna creció, lo dice', (tester) async {
    await pumpScreen(tester);

    expect(find.text(es.grownNotesEmpty), findsOneWidget);
  });

  testWidgets('tocar una abre su detalle', (tester) async {
    await seedNote('a', title: 'Roma');
    await pumpScreen(tester);

    await tester.tap(find.text('Roma'));
    await tester.pumpAndSettle();

    expect(find.text('detalle de a'), findsOneWidget);
  });

  testWidgets('se abre con el router real', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();

    harness.goTo(RoutePaths.grownNotes);
    await tester.pumpAndSettle();

    expect(find.byType(GrownNotesScreen), findsOneWidget);
  });
}
