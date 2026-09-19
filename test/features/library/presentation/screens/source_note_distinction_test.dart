import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/explorer/presentation/screens/explorer_screen.dart';
import 'package:sinapsis/features/graph/presentation/screens/graph_screen.dart';
import 'package:sinapsis/features/graph/presentation/widgets/compact_graph_node.dart';
import 'package:sinapsis/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:sinapsis/features/inbox/presentation/widgets/swipe_card.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_kanban_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_table_view.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/timeline_event_bar.dart';

import '../../../../support/library_harness.dart';
import '../../../timeline/timeline_fixtures.dart';

/// Una fuente y una nota se distinguen a simple vista en cada pantalla donde
/// aparecen, sin leer el tipo. Cada pantalla comprueba lo mismo con su propio
/// dibujo: la forma de la tarjeta, su fondo y su contorno salen del rol del
/// elemento —ver `EntityRole`—.
void main() {
  late LibraryHarness harness;
  final now = DateTime(2026, 9, 18, 10);

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  ColorScheme schemeOf(WidgetTester tester, Finder within) =>
      Theme.of(tester.element(within.first)).colorScheme;

  /// Guarda una fuente de la web, ya procesada, con [title].
  Future<KnowledgeItem> seedSource(String title) async {
    final item = KnowledgeItem(
      id: 'fuente',
      title: title,
      source: Source(
        id: 'src-fuente',
        kind: SourceKind.webPage,
        capturedAt: now,
        url: 'https://ejemplo.org/fuente',
      ),
      processingState: ProcessingState.ready,
      createdAt: now,
      updatedAt: now,
    );
    await harness.container.read(libraryRepositoryProvider).save(item);
    return item;
  }

  /// Captura una nota manual con [title].
  Future<KnowledgeItem> seedNote(String title) async {
    await harness.capture(title);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.firstWhere((i) => i.title == title);
  }

  Future<(KnowledgeItem, KnowledgeItem)> seedBoth() async =>
      (await seedSource('Una fuente'), await seedNote('Una nota'));

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(screen));
    await tester.pumpAndSettle();
  }

  group('el lenguaje', () {
    test('una nota manual es una nota y todo lo demás es una fuente', () {
      expect(SourceKind.manualNote.role, EntityRole.note);
      for (final kind in SourceKind.values.where(
        (k) => k != SourceKind.manualNote,
      )) {
        expect(kind.role, EntityRole.source, reason: kind.name);
      }
    });

    test('fuente y nota difieren en color, fondo, contorno y esquinas', () {
      for (final scheme in [
        ColorScheme.fromSeed(seedColor: Colors.teal),
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ]) {
        expect(
          EntityRole.source.accent(scheme),
          isNot(EntityRole.note.accent(scheme)),
        );
        expect(
          EntityRole.source.surface(scheme),
          isNot(EntityRole.note.surface(scheme)),
        );
        expect(
          EntityRole.source.outline(scheme),
          isNot(EntityRole.note.outline(scheme)),
        );
      }
      expect(EntityRole.source.radius, lessThan(EntityRole.note.radius));
    });

    test('la fuente es casi recta y la nota muy redondeada', () {
      expect(EntityRole.source.radius, lessThanOrEqualTo(8));
      expect(EntityRole.note.radius, greaterThanOrEqualTo(16));
    });
  });

  group('biblioteca', () {
    Material cardOf(WidgetTester tester, String title) =>
        tester.widget<Material>(
          find
              .descendant(
                of: find.widgetWithText(LibraryItemCard, title),
                matching: find.byType(Material),
              )
              .first,
        );

    testWidgets('la lista dibuja distinto una fuente y una nota', (
      tester,
    ) async {
      await seedBoth();
      await pump(tester, const LibraryScreen());
      final scheme = schemeOf(tester, find.byType(LibraryItemCard));

      final source = cardOf(tester, 'Una fuente');
      final note = cardOf(tester, 'Una nota');

      expect(
        source.borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(note.borderRadius, BorderRadius.circular(EntityRole.note.radius));
      expect(source.color, EntityRole.source.surface(scheme));
      expect(note.color, EntityRole.note.surface(scheme));
    });

    testWidgets('también en los resultados de una búsqueda', (tester) async {
      await seedBoth();
      await pump(tester, const LibraryScreen());

      await tester.enterText(find.byType(TextField).first, 'Una');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(
        cardOf(tester, 'Una fuente').borderRadius,
        isNot(cardOf(tester, 'Una nota').borderRadius),
      );
    });

    testWidgets('el tablero dibuja distinto una fuente y una nota', (
      tester,
    ) async {
      final (source, note) = await seedBoth();
      await pump(tester, LibraryKanbanView(items: [source, note]));
      final scheme = schemeOf(tester, find.byType(Card));

      RoundedRectangleBorder shapeOf(String title) =>
          tester
                  .widget<Card>(
                    find
                        .ancestor(
                          of: find.text(title),
                          matching: find.byType(Card),
                        )
                        .first,
                  )
                  .shape!
              as RoundedRectangleBorder;

      expect(
        shapeOf('Una fuente').borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(
        shapeOf('Una nota').borderRadius,
        BorderRadius.circular(EntityRole.note.radius),
      );
      expect(
        tester
            .widget<Card>(
              find
                  .ancestor(
                    of: find.text('Una fuente'),
                    matching: find.byType(Card),
                  )
                  .first,
            )
            .color,
        EntityRole.source.surface(scheme),
      );
      expect(
        tester
            .widget<Card>(
              find
                  .ancestor(
                    of: find.text('Una nota'),
                    matching: find.byType(Card),
                  )
                  .first,
            )
            .color,
        EntityRole.note.surface(scheme),
      );
    });

    testWidgets('la tabla colorea el ícono según lo que es', (tester) async {
      final (source, note) = await seedBoth();
      await pump(
        tester,
        Scaffold(body: LibraryTableView(items: [source, note])),
      );
      final scheme = schemeOf(tester, find.byType(LibraryTableView));

      final sourceIcon = tester.widget<Icon>(
        find.byIcon(SourceKind.webPage.icon),
      );
      final noteIcon = tester.widget<Icon>(
        find.byIcon(SourceKind.manualNote.icon),
      );

      expect(sourceIcon.color, EntityRole.source.accent(scheme));
      expect(noteIcon.color, EntityRole.note.accent(scheme));
      expect(sourceIcon.color, isNot(noteIcon.color));
    });
  });

  group('explorador', () {
    testWidgets('dibuja distinto una fuente y una nota', (tester) async {
      await seedBoth();
      await pump(tester, const ExplorerScreen());

      Material cardOf(String title) => tester.widget<Material>(
        find
            .descendant(
              of: find.widgetWithText(LibraryItemCard, title),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(
        cardOf('Una fuente').borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(
        cardOf('Una nota').borderRadius,
        BorderRadius.circular(EntityRole.note.radius),
      );
    });
  });

  group('grafo', () {
    Future<void> linkBoth() async {
      final (source, note) = await seedBoth();
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: note.id,
            toItemId: source.id,
            kind: RelationKind.cites,
          );
    }

    testWidgets('el grafo completo dibuja distinto una fuente y una nota', (
      tester,
    ) async {
      await linkBoth();
      await pump(tester, const GraphScreen());

      BoxDecoration decorationOf(String title) =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: find.text(title),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      expect(
        decorationOf('Una fuente').borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(
        decorationOf('Una nota').borderRadius,
        BorderRadius.circular(EntityRole.note.radius),
      );
      expect(
        decorationOf('Una fuente').color,
        isNot(decorationOf('Una nota').color),
      );
    });

    testWidgets('el nodo del grafo local también', (tester) async {
      final (source, note) = await seedBoth();
      await pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CompactGraphNode(item: source, isSeed: false),
                CompactGraphNode(item: note, isSeed: false),
              ],
            ),
          ),
        ),
      );

      BoxDecoration decorationOf(String title) =>
          tester
                  .widget<Container>(
                    find
                        .ancestor(
                          of: find.text(title),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      expect(
        decorationOf('Una fuente').borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(
        decorationOf('Una nota').borderRadius,
        BorderRadius.circular(EntityRole.note.radius),
      );
    });
  });

  group('bandeja', () {
    testWidgets('la tarjeta de una fuente es la de una fuente', (tester) async {
      await seedSource('Una fuente');
      await pump(tester, const InboxScreen());
      final scheme = schemeOf(tester, find.byType(SwipeCard));

      final card = tester.widget<Card>(
        find.descendant(
          of: find.byType(SwipeCard),
          matching: find.byType(Card),
        ),
      );

      expect(
        (card.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(EntityRole.source.radius),
      );
      expect(card.color, EntityRole.source.surface(scheme));
    });
  });

  group('línea de tiempo', () {
    testWidgets('la barra de una nota y la de una fuente tienen otro color', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              for (final (id, kind) in [
                ('fuente', SourceKind.webPage),
                ('nota', SourceKind.manualNote),
              ])
                SizedBox(
                  width: 300,
                  height: 40,
                  child: TimelineEventBar(
                    event: eventAt(id, dateOf(476), sourceKind: kind),
                    width: 300,
                    pxPerYear: 10,
                    labelOffset: 0,
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      );
      final scheme = schemeOf(tester, find.byType(TimelineEventBar));

      Color colorOf(String id) =>
          (tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: find.byWidgetPredicate(
                            (w) =>
                                w is TimelineEventBar && w.event.itemId == id,
                          ),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter!
                  as TimelineBarPainter)
              .color;

      expect(colorOf('fuente'), EntityRole.source.accent(scheme));
      expect(colorOf('nota'), EntityRole.note.accent(scheme));
      expect(colorOf('fuente'), isNot(colorOf('nota')));
    });
  });
}
