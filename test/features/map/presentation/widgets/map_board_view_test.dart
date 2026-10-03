import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/presentation/widgets/map_board_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// El tablero del mapa (F14) como widget: lo que muestra cada tarjeta y adónde
/// lleva cada fila. Sin base de datos: un mapa y un tablero armados a mano.
void main() {
  final es = AppLocalizationsEs();

  /// Roma y Grecia unidas por dos elementos y una relación; Egipto solo.
  KnowledgeMapSnapshot mapSnapshot({int isolated = 1}) {
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
    );
  }

  MapDashboard dashboard({
    List<OpenContradiction> open = const [],
    int openCount = 0,
    Map<NoteMaturity, int> maturity = const {},
    int notes = 0,
  }) => MapDashboard(
    itemCount: 4,
    sourceCount: 4 - notes,
    noteCount: notes,
    openContradictionCount: openCount,
    openContradictions: open,
    growth: const [
      GrowthPoint(year: 2026, month: 1, added: 1, total: 1),
      GrowthPoint(year: 2026, month: 2, added: 2, total: 3),
      GrowthPoint(year: 2026, month: 3, added: 1, total: 4),
    ],
    maturity: maturity,
  );

  Future<List<String>> pump(
    WidgetTester tester, {
    KnowledgeMapSnapshot? snapshot,
    MapDashboard? dash,
  }) async {
    final calls = <String>[];
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MapBoardView(
            snapshot: snapshot ?? mapSnapshot(),
            dimension: const TopicDimension.spaces(),
            dashboard: dash,
            onOpenTopic: (id) => calls.add('topic:$id'),
            onOpenItem: (id) => calls.add('item:$id'),
            onOpenTension: () => calls.add('tension'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('resume: cuántos temas y comunidades, y cuántos elementos', (
    tester,
  ) async {
    await pump(tester, dash: dashboard());

    expect(find.text(es.mapTopicCount('spaces', 3)), findsOneWidget);
    expect(find.text(es.mapCommunityCount(1)), findsOneWidget);
    expect(find.text(es.mapItemCount(4)), findsWidgets);
  });

  testWidgets('los temas con más material, de más a menos', (tester) async {
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
    // Roma: 3; Grecia: 2; Egipto: 1.
    expect(roma.dy, lessThan(grecia.dy));
    expect(grecia.dy, lessThan(egipto.dy));
  });

  testWidgets('tocar un tema, un par o un aislado abre ese tema', (
    tester,
  ) async {
    final calls = await pump(tester, snapshot: mapSnapshot(isolated: 2));

    await tester.tap(find.byKey(const ValueKey('map-densest-roma')));
    await tester.tap(find.byKey(const ValueKey('map-pair-grecia-roma')));
    await tester.tap(find.byKey(const ValueKey('map-isolated-egipto')));

    expect(calls, ['topic:roma', 'topic:grecia', 'topic:egipto']);
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

  testWidgets('los aislados dicen cuántos hay y cuántos quedaron sin mostrar', (
    tester,
  ) async {
    await pump(tester, snapshot: mapSnapshot(isolated: 12));

    // Egipto y once más: 12 en total, y solo ocho a la vista.
    expect(
      find.textContaining('${es.mapBoardIsolatedTitle('spaces')} (12)'),
      findsOneWidget,
    );
    expect(find.text(es.mapBoardMore(4)), findsOneWidget);
  });

  testWidgets('sin aislados, la tarjeta no aparece', (tester) async {
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

    await pump(tester, snapshot: snapshot);

    expect(find.byKey(const ValueKey('map-board-isolated')), findsNothing);
  });

  group('con el tablero', () {
    testWidgets('sin él, no hay tarjetas de contradicciones, crecimiento ni '
        'madurez', (tester) async {
      await pump(tester);

      expect(
        find.byKey(const ValueKey('map-board-contradictions')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('map-board-growth')), findsNothing);
      expect(find.byKey(const ValueKey('map-board-maturity')), findsNothing);
    });

    testWidgets('las contradicciones abiertas: títulos, y adónde lleva cada '
        'cosa', (tester) async {
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

      expect(find.text('Plutarco  ↔  Polibio'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-contradiction-r1')));
      await tester.tap(find.byKey(const ValueKey('map-contradictions-all')));

      expect(calls, ['item:a', 'tension']);
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

    testWidgets('el crecimiento: el rango de meses, el total y una '
        'descripción accesible', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, dash: dashboard());

      final card = find.byKey(const ValueKey('map-board-growth'));
      expect(card, findsOneWidget);
      // La tarjeta junta lo que dice en un solo nodo: el título y el gráfico.
      expect(
        tester.getSemantics(card).label,
        contains(es.mapBoardGrowthSemantics(4, 3)),
      );
      handle.dispose();
    });

    testWidgets('la madurez cuenta las notas de cada grado', (tester) async {
      await pump(
        tester,
        dash: dashboard(
          notes: 5,
          maturity: {
            NoteMaturity.seed: 3,
            NoteMaturity.developing: 1,
            NoteMaturity.mature: 1,
          },
        ),
      );

      expect(find.text('${es.noteMaturitySeed}: 3'), findsOneWidget);
      expect(find.text('${es.noteMaturityMature}: 1'), findsOneWidget);
    });

    testWidgets('sin notas, la madurez lo dice', (tester) async {
      await pump(tester, dash: dashboard());

      expect(find.text(es.mapBoardMaturityNone), findsOneWidget);
    });
  });
}
