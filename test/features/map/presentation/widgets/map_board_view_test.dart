import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/processed_depth.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/stats_charts.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/domain/services/board_insights.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_target.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El Resumen del Mapa (F14, rehecho en F44 paso 3) como widget: lo que
/// muestra cada tarjeta, adónde lleva cada cosa —al Mapa, decisión D— y que
/// entra en un teléfono con la letra al doble, en claro y en oscuro, con el
/// lector de pantalla. Sin base de datos: un mapa, un tablero y lo que se
/// cuenta aparte, armados a mano.
void main() {
  final es = AppLocalizationsEs();
  final now = DateTime(2026, 10, 30, 12);
  DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  /// Roma y Grecia unidas por dos documentos y una contradicción; Egipto solo.
  KnowledgeMapSnapshot mapSnapshot({
    int isolated = 1,
    List<String> unassigned = const [],
  }) {
    final input = TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: [
        const AtlasValueRow(id: 'roma', label: 'Roma'),
        const AtlasValueRow(id: 'grecia', label: 'Grecia'),
        const AtlasValueRow(id: 'egipto', label: 'Egipto'),
        for (var i = 0; i < isolated - 1; i++)
          AtlasValueRow(id: 'solo$i', label: 'Solo $i'),
      ],
      items: const [
        TopicItem(id: 'a', valueIds: ['roma', 'grecia']),
        TopicItem(id: 'b', valueIds: ['roma', 'grecia']),
        TopicItem(id: 'c', valueIds: ['roma']),
        TopicItem(id: 'd', valueIds: ['egipto']),
      ],
      relations: const [
        TopicRelation(
          fromItemId: 'a',
          toItemId: 'b',
          kind: RelationKind.contradicts,
        ),
      ],
    );
    final computed = computeMap(input, const CommunityMemory.none());
    return KnowledgeMapSnapshot(
      request: const MapRequest('tema'),
      graph: computed.graph,
      detection: computed.detection,
      timings: const MapTimings(
        read: Duration.zero,
        build: Duration.zero,
        communities: Duration.zero,
        total: Duration.zero,
      ),
      sequence: 1,
      unassignedItemIds: unassigned,
    );
  }

  /// Lo que se cuenta aparte del mapa: a y d llegaron esta semana, b hace 10
  /// días y c hace 40; a y b se vincularon hace 3 días; c tiene dos tarjetas,
  /// una para hoy, y a una que no toca.
  BoardInsights insightsOf(KnowledgeMapSnapshot snapshot) => buildBoardInsights(
    graph: snapshot.graph,
    detection: snapshot.detection,
    facts: BoardFacts(
      items: [
        BoardItemFact(
          id: 'a',
          title: 'Plutarco',
          createdAt: daysAgo(2),
          valueIds: const ['roma', 'grecia'],
        ),
        BoardItemFact(
          id: 'b',
          title: 'Polibio',
          createdAt: daysAgo(10),
          valueIds: const ['roma', 'grecia'],
        ),
        BoardItemFact(
          id: 'c',
          title: 'Tito Livio',
          createdAt: daysAgo(40),
          valueIds: const ['roma'],
        ),
        BoardItemFact(
          id: 'd',
          title: 'Heródoto',
          createdAt: daysAgo(1),
          valueIds: const ['egipto'],
        ),
      ],
      links: [BoardLinkFact(fromId: 'a', toId: 'b', createdAt: daysAgo(3))],
    ),
    cards: const {
      'a': BoardCardFact(cards: 1, dueToday: 0),
      'c': BoardCardFact(cards: 2, dueToday: 1),
    },
    now: now,
  );

  MapDashboard dashboard({
    List<OpenContradiction> open = const [],
    int openCount = 0,
    Map<ProcessedDepth, int> depth = const {},
    int items = 4,
  }) => MapDashboard(
    itemCount: items,
    openContradictionCount: openCount,
    openContradictions: open,
    growth: const [
      GrowthPoint(year: 2026, month: 1, added: 1, total: 1),
      GrowthPoint(year: 2026, month: 2, added: 2, total: 3),
      GrowthPoint(year: 2026, month: 3, added: 1, total: 4),
    ],
    depth: depth,
  );

  Future<List<Object>> pump(
    WidgetTester tester, {
    KnowledgeMapSnapshot? snapshot,
    MapDashboard? dash,
    BoardInsights? insights,
    bool withInsights = true,
    Size size = const Size(900, 4000),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final calls = <Object>[];
    final map = snapshot ?? mapSnapshot();
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: MapBoardView(
              snapshot: map,
              dimension: const TopicDimension.spaces(),
              dashboard: dash,
              insights: withInsights ? insights ?? insightsOf(map) : null,
              onShowInMap: calls.add,
              onOpenItem: (id) => calls.add('item:$id'),
              onOpenTension: () => calls.add('tension'),
              onStudyTopic: (id) => calls.add('study:$id'),
              onSuggestLinks: (ids) => calls.add('suggest:${ids.join(',')}'),
              onOrganize: (ids) => calls.add('organize:${ids.join(',')}'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  group('las cifras grandes', () {
    testWidgets('documentos, temas, comunidades y vínculos, con lo que '
        'sumaron en 30 días', (tester) async {
      await pump(tester);

      Finder figure(String name) =>
          find.byKey(ValueKey('map-board-figure-$name'));
      String textsOf(String name) => tester
          .widgetList<Text>(
            find.descendant(of: figure(name), matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .join(' | ');

      // Cuatro documentos, tres de este mes; tres temas, Grecia y Egipto
      // nuevos; una comunidad, que ya existía; un vínculo, nuevo.
      expect(
        textsOf('documents'),
        '4 | ${es.f44S3FigureDocuments(4)} | ${es.f44S3FigureAdded(3)}',
      );
      expect(
        textsOf('topics'),
        '3 | ${es.f44S3FigureTopics('spaces', 3)} | ${es.f44S3FigureAdded(2)}',
      );
      expect(
        textsOf('communities'),
        '1 | ${es.f44S3FigureCommunities(1)} | ${es.f44S3FigureSteady}',
      );
      expect(
        textsOf('links'),
        '1 | ${es.f44S3FigureLinks(1)} | ${es.f44S3FigureAdded(1)}',
      );
    });

    testWidgets('tocar cada una abre el Mapa a su altura', (tester) async {
      final calls = await pump(tester);

      for (final figure in MapBoardFigure.values) {
        await tester.tap(
          find.byKey(ValueKey('map-board-figure-${figure.name}')),
        );
      }

      expect(calls, [for (final f in MapBoardFigure.values) MapBoardLevel(f)]);
    });

    testWidgets('sin lo que se cuenta aparte, lo que no se sabe es una raya y '
        'no se inventa ningún cambio', (tester) async {
      await pump(tester, withInsights: false);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-board-figure-links')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('30 días'), findsNothing);
      // Lo que sale de lo que se cuenta aparte espera.
      expect(find.byKey(const ValueKey('map-board-new')), findsNothing);
      expect(find.byKey(const ValueKey('map-board-study')), findsNothing);
    });

    testWidgets('con el lector de pantalla, cada cifra es un botón que dice '
        'todo y se puede tocar', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = await pump(tester);

      final node = tester.getSemantics(
        find.byKey(const ValueKey('map-board-figure-documents')),
      );
      expect(
        node,
        isSemantics(
          label: '4, ${es.f44S3FigureDocuments(4)}, ${es.f44S3FigureAdded(3)}',
          hint: es.f44S3OpenMapHint,
          isButton: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(
        find.semantics.byLabel(
          '4, ${es.f44S3FigureDocuments(4)}, ${es.f44S3FigureAdded(3)}',
        ),
      );
      expect(calls, [const MapBoardLevel(MapBoardFigure.documents)]);
      handle.dispose();
    });
  });

  group('lo nuevo de la semana', () {
    testWidgets('lo procesado y lo vinculado, lo último primero; tocarlo lo '
        'muestra en el Mapa', (tester) async {
      final calls = await pump(tester);

      expect(find.text(es.f44S3NewDocuments(2)), findsOneWidget);
      expect(find.text(es.f44S3NewLinks(1)), findsOneWidget);
      final herodotus = tester.getTopLeft(
        find.byKey(const ValueKey('map-new-item-d')),
      );
      final plutarco = tester.getTopLeft(
        find.byKey(const ValueKey('map-new-item-a')),
      );
      expect(herodotus.dy, lessThan(plutarco.dy));
      // Polibio llegó hace 10 días: no es de esta semana.
      expect(find.byKey(const ValueKey('map-new-item-b')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('map-new-item-d')));
      await tester.tap(find.byKey(const ValueKey('map-new-link-a-b')));
      expect(calls, [const MapBoardItem('d'), const MapBoardItem('a')]);
    });

    testWidgets('sin nada nuevo, lo dice', (tester) async {
      final snapshot = mapSnapshot();
      await pump(
        tester,
        snapshot: snapshot,
        insights: buildBoardInsights(
          graph: snapshot.graph,
          detection: snapshot.detection,
          facts: const BoardFacts.empty(),
          cards: const {},
          now: now,
        ),
      );

      expect(find.text(es.f44S3NewNone), findsOneWidget);
    });
  });

  group('para estudiar', () {
    testWidgets('los temas con tarjetas para hoy y los que tienen material '
        'sin tarjetas', (tester) async {
      await pump(tester);

      expect(find.text(es.f44S3StudyDueHeading), findsOneWidget);
      expect(find.text(es.f44S3StudyDue(1)), findsOneWidget);
      expect(find.byKey(const ValueKey('map-study-due-roma')), findsOneWidget);
      expect(find.text(es.f44S3StudyUncarded(1)), findsOneWidget);
      expect(
        find.byKey(const ValueKey('map-study-uncarded-egipto')),
        findsOneWidget,
      );
      // Grecia tiene una tarjeta, que no toca hoy: no está en ninguna.
      expect(find.byKey(const ValueKey('map-study-due-grecia')), findsNothing);
      expect(
        find.byKey(const ValueKey('map-study-uncarded-grecia')),
        findsNothing,
      );
    });

    testWidgets('«Estudiar» abre Repasar con el tema; la fila, el Mapa', (
      tester,
    ) async {
      final calls = await pump(tester);

      await tester.tap(find.byKey(const ValueKey('map-study-due-action-roma')));
      await tester.tap(
        find.byKey(const ValueKey('map-study-uncarded-action-egipto')),
      );
      await tester.tap(find.byKey(const ValueKey('map-study-due-roma')));

      expect(calls, [
        'study:roma',
        'study:egipto',
        const MapBoardTopic('roma'),
      ]);
    });

    testWidgets('el lector de pantalla nombra el tema en el botón', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('map-study-due-action-roma')),
        ),
        isSemantics(
          label: es.f44S3StudySemantics('Roma'),
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('todo al día, lo dice', (tester) async {
      final snapshot = mapSnapshot();
      await pump(
        tester,
        snapshot: snapshot,
        insights: buildBoardInsights(
          graph: snapshot.graph,
          detection: snapshot.detection,
          facts: const BoardFacts.empty(),
          cards: const {},
          now: now,
        ),
      );

      expect(find.text(es.f44S3StudyNone), findsOneWidget);
    });
  });

  group('los temas con más material', () {
    testWidgets('de más a menos, con el número y el porcentaje del total', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(es.mapBoardDensestTitle('spaces')), findsOneWidget);
      final roma = tester.getTopLeft(
        find.byKey(const ValueKey('map-densest-roma')),
      );
      final grecia = tester.getTopLeft(
        find.byKey(const ValueKey('map-densest-grecia')),
      );
      final egipto = tester.getTopLeft(
        find.byKey(const ValueKey('map-densest-egipto')),
      );
      // Roma: 3 de 4; Grecia: 2; Egipto: 1.
      expect(roma.dy, lessThan(grecia.dy));
      expect(grecia.dy, lessThan(egipto.dy));
      expect(find.text(es.f44S3DensestShare(3, 75)), findsOneWidget);
      expect(find.text(es.f44S3DensestShare(2, 50)), findsOneWidget);
      expect(find.text(es.f44S3DensestShare(1, 25)), findsOneWidget);
    });

    testWidgets('tocar un tema, un par, un puente o un aislado lleva al Mapa '
        'con ese tema en foco, no al Explorador', (tester) async {
      final calls = await pump(tester, snapshot: mapSnapshot(isolated: 2));

      await tester.tap(find.byKey(const ValueKey('map-densest-roma')));
      await tester.tap(find.byKey(const ValueKey('map-pair-grecia-roma')));
      await tester.tap(find.byKey(const ValueKey('map-isolated-egipto')));

      expect(calls, [
        const MapBoardTopic('roma'),
        const MapBoardTopic('grecia'),
        const MapBoardTopic('egipto'),
      ]);
    });
  });

  testWidgets(
    'el par más conectado marca la tensión si hay una contradicción',
    (tester) async {
      await pump(tester);

      final pair = find.byKey(const ValueKey('map-pair-grecia-roma'));
      expect(pair, findsOneWidget);
      expect(
        find.descendant(of: pair, matching: find.byIcon(Icons.bolt)),
        findsOneWidget,
      );
    },
  );

  testWidgets('sin puentes, la tarjeta lo dice', (tester) async {
    // Roma y Grecia son una sola comunidad de dos: ninguno une partes.
    await pump(tester);

    expect(find.text(es.f44S3BridgesTitle), findsOneWidget);
    expect(find.text(es.f44S3BridgesNone), findsOneWidget);
  });

  testWidgets('un puente dice qué une, y tocarlo lo pone en foco', (
    tester,
  ) async {
    // Una cadena Roma ─ Grecia ─ Egipto: Grecia, en el medio, la sostiene.
    const input = TopicGraphInput(
      definitionId: 'tema',
      definitionName: 'Tema',
      values: [
        AtlasValueRow(id: 'roma', label: 'Roma'),
        AtlasValueRow(id: 'grecia', label: 'Grecia'),
        AtlasValueRow(id: 'egipto', label: 'Egipto'),
      ],
      items: [
        TopicItem(id: 'a', valueIds: ['roma', 'grecia']),
        TopicItem(id: 'b', valueIds: ['grecia', 'egipto']),
      ],
      relations: [],
    );
    final computed = computeMap(input, const CommunityMemory.none());
    final snapshot = KnowledgeMapSnapshot(
      request: const MapRequest('tema'),
      graph: computed.graph,
      detection: computed.detection,
      timings: const MapTimings(
        read: Duration.zero,
        build: Duration.zero,
        communities: Duration.zero,
        total: Duration.zero,
      ),
      sequence: 1,
    );
    final calls = await pump(tester, snapshot: snapshot, withInsights: false);

    final bridge = find.byKey(const ValueKey('map-bridge-grecia'));
    expect(bridge, findsOneWidget);
    await tester.tap(bridge);
    expect(calls, [const MapBoardTopic('grecia')]);
  });

  group('sueltos y aislados', () {
    testWidgets('los temas aislados y los documentos sin vínculos, con sus '
        'salidas', (tester) async {
      final calls = await pump(
        tester,
        snapshot: mapSnapshot(isolated: 12, unassigned: ['e']),
      );

      // Egipto y once más: 12 en total, y solo ocho a la vista.
      expect(
        find.textContaining('${es.mapBoardIsolatedTitle('spaces')} (12)'),
        findsOneWidget,
      );
      expect(find.text(es.mapBoardMore(4)), findsOneWidget);
      // Tito Livio y Heródoto no tienen ningún vínculo.
      expect(find.text(es.f44S3LooseDocuments(2)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-loose-c')));
      await tester.tap(find.byKey(const ValueKey('map-loose-suggest')));
      await tester.tap(find.byKey(const ValueKey('map-loose-organize')));

      expect(calls, [
        // Un suelto no tiene vínculos que ver en el Mapa: se abre.
        'item:c',
        // Lo último que llegó, primero.
        'suggest:d,c',
        // Lo suelto y lo que no tiene tema, sin repetir.
        'organize:d,c,e',
      ]);
    });

    testWidgets('con un solo documento suelto no hay entre qué sugerir', (
      tester,
    ) async {
      final snapshot = mapSnapshot();
      final insights = buildBoardInsights(
        graph: snapshot.graph,
        detection: snapshot.detection,
        facts: BoardFacts(
          items: [
            BoardItemFact(
              id: 'c',
              title: 'Tito Livio',
              createdAt: daysAgo(40),
              valueIds: const ['roma'],
            ),
          ],
          links: const [],
        ),
        cards: const {},
        now: now,
      );
      await pump(tester, snapshot: snapshot, insights: insights);

      expect(find.byKey(const ValueKey('map-loose-suggest')), findsNothing);
      expect(find.byKey(const ValueKey('map-loose-organize')), findsOneWidget);
    });

    testWidgets('sin nada suelto, lo dice', (tester) async {
      const input = TopicGraphInput(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: [
          AtlasValueRow(id: 'a', label: 'A'),
          AtlasValueRow(id: 'b', label: 'B'),
        ],
        items: [
          TopicItem(id: 'i', valueIds: ['a', 'b']),
        ],
        relations: [],
      );
      final computed = computeMap(input, const CommunityMemory.none());
      final snapshot = KnowledgeMapSnapshot(
        request: const MapRequest('tema'),
        graph: computed.graph,
        detection: computed.detection,
        timings: const MapTimings(
          read: Duration.zero,
          build: Duration.zero,
          communities: Duration.zero,
          total: Duration.zero,
        ),
        sequence: 1,
      );
      final insights = buildBoardInsights(
        graph: snapshot.graph,
        detection: snapshot.detection,
        facts: const BoardFacts.empty(),
        cards: const {},
        now: now,
      );

      await pump(tester, snapshot: snapshot, insights: insights);

      expect(find.text(es.f44S3LooseNone), findsOneWidget);
      expect(find.byKey(const ValueKey('map-loose-organize')), findsNothing);
    });
  });

  group('con el tablero', () {
    testWidgets('sin él, no hay tarjetas de contradicciones, crecimiento ni '
        'trabajo', (tester) async {
      await pump(tester);

      expect(
        find.byKey(const ValueKey('map-board-contradictions')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('map-board-growth')), findsNothing);
      expect(find.byKey(const ValueKey('map-board-depth')), findsNothing);
    });

    testWidgets('las contradicciones abiertas: la fila lleva al Mapa y «ver '
        'todas», a Tensión', (tester) async {
      final calls = await pump(
        tester,
        dash: dashboard(
          openCount: 7,
          open: const [
            OpenContradiction(
              relationId: 'r1',
              fromId: 'a',
              fromTitle: 'Plutarco',
              toId: 'b',
              toTitle: 'Polibio',
            ),
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('map-contradiction-r1')),
          matching: find.text('Plutarco  ↔  Polibio'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('map-contradiction-r1')));
      await tester.tap(find.byKey(const ValueKey('map-contradictions-all')));

      expect(calls, [const MapBoardItem('a'), 'tension']);
      expect(find.text(es.mapBoardContradictionsAll(7)), findsOneWidget);
    });

    testWidgets('sin contradicciones abiertas lo dice', (tester) async {
      await pump(tester, dash: dashboard());

      expect(find.text(es.mapBoardContradictionsNone), findsOneWidget);
      expect(
        find.byKey(const ValueKey('map-contradictions-all')),
        findsNothing,
      );
    });

    testWidgets('cómo creció: una columna por mes con su eje, el total y el '
        'resumen para el lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, dash: dashboard());

      final chart = tester.widget<StatsBarChart>(
        find.byKey(const ValueKey('map-board-growth-chart')),
      );
      expect([for (final b in chart.bars) b.total], [1, 2, 1]);
      // Las puntas, con el año.
      expect(chart.xLabels.keys, containsAll([0, 2]));
      expect(chart.xLabels[0], contains('2026'));
      expect(find.text(es.f44S3GrowthTotal(4)), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('map-board-growth-chart')))
            .label,
        allOf(
          contains(es.f44S3GrowthChartLabel(3)),
          contains(es.f44S3GrowthBar('feb 2026', 2, 3)),
        ),
      );
      handle.dispose();
    });

    testWidgets('lo trabajado cuenta los documentos de cada escalón (F41)', (
      tester,
    ) async {
      await pump(
        tester,
        dash: dashboard(
          depth: {
            ProcessedDepth.textOnly: 2,
            ProcessedDepth.cut: 1,
            ProcessedDepth.annotated: 1,
          },
        ),
      );

      expect(find.text(es.mapBoardDepthTitle), findsOneWidget);
      expect(find.text('${es.processedDepthTextOnly}: 2'), findsOneWidget);
      expect(find.text('${es.processedDepthSummarized}: 0'), findsOneWidget);
      expect(find.text('${es.processedDepthAnnotated}: 1'), findsOneWidget);
    });

    testWidgets('sin documentos, lo trabajado lo dice', (tester) async {
      await pump(tester, dash: dashboard(items: 0));

      expect(find.text(es.mapBoardDepthNone), findsOneWidget);
    });
  });

  testWidgets('en un teléfono de 360 dp con la letra al doble entra todo, en '
      'claro y en oscuro, y «Estudiar» baja debajo del tema', (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await pump(
        tester,
        dash: dashboard(
          openCount: 1,
          open: const [
            OpenContradiction(
              relationId: 'r1',
              fromId: 'a',
              fromTitle: 'Un título larguísimo de una fuente procesada',
              toId: 'b',
              toTitle: 'Otro título igual de largo, para que no entre',
            ),
          ],
          depth: {ProcessedDepth.textOnly: 3, ProcessedDepth.annotated: 1},
        ),
        snapshot: mapSnapshot(isolated: 6, unassigned: ['e']),
        size: const Size(360, 800),
        textScale: 2,
        theme: theme,
      );

      // Se recorre la lista entera: cada tarjeta se arma y se mide.
      final list = find.byType(Scrollable).first;
      for (final key in [
        'map-board-study',
        'map-board-bridges',
        'map-board-loose',
        'map-board-growth',
        'map-board-depth',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          300,
          scrollable: list,
        );
        expect(tester.takeException(), isNull, reason: key);
      }
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('map-study-due-action-roma')),
        -300,
        scrollable: list,
      );
      final row = tester.getRect(
        find.byKey(const ValueKey('map-study-due-roma')),
      );
      final button = tester.getRect(
        find.byKey(const ValueKey('map-study-due-action-roma')),
      );
      expect(button.top, greaterThanOrEqualTo(row.bottom));
    }
  });

  testWidgets('con la letra normal, «Estudiar» va al lado del tema', (
    tester,
  ) async {
    await pump(tester, size: const Size(360, 4000));

    final row = tester.getRect(
      find.byKey(const ValueKey('map-study-due-roma')),
    );
    final button = tester.getRect(
      find.byKey(const ValueKey('map-study-due-action-roma')),
    );
    expect(button.left, greaterThanOrEqualTo(row.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('las filas, para el lector de pantalla, son botones con su '
      'nombre y su acción', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = await pump(tester);

    expect(
      tester.getSemantics(find.byKey(const ValueKey('map-densest-roma'))),
      isSemantics(
        label: es.f44S3DensestSemantics('Roma', 3, 75),
        hint: es.f44S3OpenMapHint,
        isButton: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(
      find.semantics.byLabel(es.f44S3DensestSemantics('Roma', 3, 75)),
    );
    expect(calls, [const MapBoardTopic('roma')]);
    // Los títulos de las tarjetas son encabezados.
    expect(
      tester.getSemantics(find.text(es.f44S3StudyTitle)),
      isSemantics(isHeader: true),
    );
    handle.dispose();
  });
}
