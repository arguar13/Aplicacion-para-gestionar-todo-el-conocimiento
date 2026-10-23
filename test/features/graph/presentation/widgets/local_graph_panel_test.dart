import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/graph/presentation/widgets/local_graph_panel.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<KnowledgeItem> capture(String title) async {
    await harness.capture(title, title: title);
    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    return items.firstWhere((i) => i.title == title);
  }

  Future<void> link(KnowledgeItem from, KnowledgeItem to) => harness.container
      .read(organizeRepositoryProvider)
      .createRelation(
        fromItemId: from.id,
        toItemId: to.id,
        kind: RelationKind.relatedTo,
      );

  /// Un elemento con [count] vecinos directos, ya vinculados.
  Future<KnowledgeItem> seedWithNeighbors(int count) async {
    final seed = await capture('el elemento central');
    for (var i = 0; i < count; i++) {
      await link(seed, await capture('vecino número $i'));
    }
    return seed;
  }

  /// El panel solo, con un router mínimo: tocar para ampliar tiene que llegar
  /// a la ruta del mapa completo del elemento.
  Future<void> pumpPanel(
    WidgetTester tester,
    KnowledgeItem item, {
    double width = 340,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: LocalGraphPanel(item: item),
              ),
            ),
          ),
        ),
        GoRoute(
          path: RoutePaths.graphLocalPattern,
          builder: (_, state) => Scaffold(
            body: Text('mapa completo de ${state.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: RoutePaths.itemDetailPattern,
          builder: (_, state) =>
              Scaffold(body: Text('detalle de ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder previewNodes() => find.byType(LocalGraphPreviewNode);
  Finder moreChip() => find.byKey(const ValueKey('local-graph-preview-more'));

  testWidgets('se muestra: el título, el elemento y sus vecinos', (
    tester,
  ) async {
    final seed = await seedWithNeighbors(2);

    await pumpPanel(tester, seed);

    expect(find.text(es.localGraphPreviewTitle), findsOneWidget);
    expect(previewNodes(), findsNWidgets(3));
    expect(find.text('el elemento central'), findsOneWidget);
    expect(find.text('vecino número 0'), findsOneWidget);
    expect(find.text('vecino número 1'), findsOneWidget);
    expect(moreChip(), findsNothing);
  });

  testWidgets('sin vínculos, dice que no hay nada y no dibuja nodos', (
    tester,
  ) async {
    final seed = await capture('un elemento solo');

    await pumpPanel(tester, seed);

    expect(find.text(es.graphEmpty), findsOneWidget);
    expect(previewNodes(), findsNothing);
  });

  testWidgets('no dibuja etiquetas de vínculo: solo nombres', (tester) async {
    final seed = await seedWithNeighbors(3);

    await pumpPanel(tester, seed);

    expect(find.text(es.relationKindLabelRelatedTo), findsNothing);
    expect(find.textContaining('Relacionado'), findsNothing);
  });

  testWidgets(
    'con muchos vecinos dibuja el tope y resume el resto en un «+N»',
    (tester) async {
      final seed = await seedWithNeighbors(14);

      await pumpPanel(tester, seed);

      // Diez vecinos y el elemento.
      expect(previewNodes(), findsNWidgets(11));
      expect(moreChip(), findsOneWidget);
      expect(find.text(es.localGraphPreviewMore(4)), findsOneWidget);
    },
  );

  testWidgets('el «+N» cuenta también los que el vecindario dejó afuera', (
    tester,
  ) async {
    // Treinta y dos vecinos: el vecindario trae veintinueve y deja tres afuera.
    final seed = await seedWithNeighbors(32);

    await pumpPanel(tester, seed);

    expect(previewNodes(), findsNWidgets(11));
    expect(find.text(es.localGraphPreviewMore(22)), findsOneWidget);
  });

  testWidgets('con muchos vecinos ningún nodo se encima ni se sale de la '
      'tarjeta, y usa todo el ancho', (tester) async {
    final seed = await seedWithNeighbors(14);

    await pumpPanel(tester, seed);

    final card = tester.getRect(find.byType(LocalGraphPanel));
    final rects = [
      for (final node in previewNodes().evaluate())
        tester.getRect(find.byWidget(node.widget)),
    ];
    for (var i = 0; i < rects.length; i++) {
      expect(
        card.contains(rects[i].topLeft) && card.contains(rects[i].bottomRight),
        isTrue,
        reason: 'el nodo $i se sale de la tarjeta',
      );
      for (var j = i + 1; j < rects.length; j++) {
        expect(
          rects[i].overlaps(rects[j]),
          isFalse,
          reason: 'los nodos $i y $j se encimaron',
        );
      }
    }
    final left = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
    final right = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    expect(right - left, greaterThan(card.width - 24));
  });

  testWidgets('un título larguísimo se corta con elipsis sin desbordar', (
    tester,
  ) async {
    final seed = await capture(
      'Un título larguísimo que no entra jamás en una '
      'píldora de la vista previa del mapa del elemento, por más que se '
      'esfuerce',
    );
    await link(seed, await capture('otro'));

    await pumpPanel(tester, seed);

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(
      find.descendant(of: previewNodes().first, matching: find.byType(Text)),
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('une al elemento con cada vecino con una línea, del centro de '
      'uno al del otro', (tester) async {
    final seed = await seedWithNeighbors(5);

    await pumpPanel(tester, seed);

    final linksFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PreviewLinksPainter,
    );
    final painter =
        tester.widget<CustomPaint>(linksFinder).painter! as PreviewLinksPainter;
    expect(painter.to, hasLength(5));
    // Las líneas parten del centro del elemento.
    final canvas = tester.getTopLeft(linksFinder);
    final seedCenter = tester.getCenter(
      find.widgetWithText(LocalGraphPreviewNode, 'el elemento central'),
    );
    expect(painter.from + canvas, offsetMoreOrLessEquals(seedCenter));
    expect(
      tester.renderObject(linksFinder),
      paintsExactlyCountTimes(#drawLine, 5),
    );
  });

  testWidgets('tocar el botón de ampliar abre el mapa completo', (
    tester,
  ) async {
    final seed = await seedWithNeighbors(2);
    await pumpPanel(tester, seed);

    await tester.tap(find.byTooltip(es.localGraphPanelOpenFull));
    await tester.pumpAndSettle();

    expect(find.text('mapa completo de ${seed.id}'), findsOneWidget);
  });

  testWidgets('tocar la vista previa abre el mapa completo', (tester) async {
    final seed = await seedWithNeighbors(2);
    await pumpPanel(tester, seed);

    // El elemento del medio no es tocable por sí mismo: el toque llega a la
    // vista.
    await tester.tap(find.text('el elemento central'));
    await tester.pumpAndSettle();

    expect(find.text('mapa completo de ${seed.id}'), findsOneWidget);
  });

  testWidgets('tocar el «+N» abre el mapa completo', (tester) async {
    final seed = await seedWithNeighbors(12);
    await pumpPanel(tester, seed);

    await tester.tap(moreChip());
    await tester.pumpAndSettle();

    expect(find.text('mapa completo de ${seed.id}'), findsOneWidget);
  });

  testWidgets('tocar un vecino va a su detalle, no al mapa', (tester) async {
    final seed = await seedWithNeighbors(2);
    await pumpPanel(tester, seed);

    await tester.tap(find.text('vecino número 0'));
    await tester.pumpAndSettle();

    expect(find.textContaining('detalle de'), findsOneWidget);
    expect(find.textContaining('mapa completo de'), findsNothing);
  });
}
