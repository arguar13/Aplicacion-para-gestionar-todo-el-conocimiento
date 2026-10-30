import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_recent.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';
import 'package:sinapsis/features/map/domain/services/bridge_finder.dart';
import 'package:sinapsis/features/map/domain/services/community_detector.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/map_recent_builder.dart';
import 'package:sinapsis/features/map/domain/services/topic_adjacency.dart';

import '../../../../benchmark/structured_topics.dart';
import 'insights_fixtures.dart';

/// Lo que el motor sabe además de las comunidades (F44, paso 1), calculado en
/// el mismo cálculo que ellas: de punta a punta, a través del isolate y con la
/// bóveda grande del benchmark del mapa.
void main() {
  final now = DateTime(2026, 10, 30, 12);
  final old = DateTime(2026, 6);
  final recent = DateTime(2026, 10, 20);

  /// Dos parejas de temas que el mes pasado eran dos islas y que lo
  /// procesado este mes juntó en una.
  TopicGraphInput merged() => inputOf(
    ['a1', 'a2', 'b1', 'b2'],
    [
      ...repeat(2, ['a1', 'a2']),
      ...repeat(2, ['b1', 'b2']),
      ...repeat(5, ['a1', 'a2', 'b1', 'b2']),
    ],
    itemDates: {
      for (var i = 0; i < 4; i++) 'i$i': old,
      for (var i = 4; i < 9; i++) 'i$i': recent,
    },
    unassigned: [
      TopicItem(
        id: 'suelto',
        valueIds: const [],
        title: 'Suelto',
        createdAt: recent,
      ),
    ],
    readAt: now,
  );

  group('de punta a punta', () {
    test('computeMap lo entrega con el mapa: nombres, búsqueda, burbuja y lo '
        'nuevo, con las comunidades de hace un mes agrupadas aparte', () {
      final computed = computeMap(merged(), const CommunityMemory.none());
      final insights = computed.insights;

      expect(connectedCommunities(computed.detection), 1);
      expect(insights.recent.figures.communities.now, 1);
      expect(
        insights.recent.figures.communities.before,
        2,
        reason: 'hace un mes eran dos islas',
      );
      expect(insights.communities.all, hasLength(1));
      expect(insights.communities.all.single.nameLabels, hasLength(2));
      expect(insights.search.document('suelto')!.isUnthemed, isTrue);
      expect(insights.unthemed.count, 1);
      expect(insights.recent.month.processedCount, 6);
      expect(computed.insightsTime, greaterThanOrEqualTo(Duration.zero));
    });

    test('sin la hora de la lectura, lo nuevo no existe pero lo demás sí', () {
      final input = merged();
      final computed = computeMap(
        TopicGraphInput(
          definitionId: input.definitionId,
          definitionName: input.definitionName,
          values: input.values,
          items: input.items,
          relations: input.relations,
          unassigned: input.unassigned,
        ),
        const CommunityMemory.none(),
      );

      expect(computed.insights.recent.at, isNull);
      expect(computed.insights.recent.figures.communities.delta, 0);
      expect(computed.insights.search.entries, hasLength(4 + 10));
    });

    test(
      'cruza el isolate de ida y de vuelta, y busca del otro lado',
      () async {
        final computed = await computeMapInIsolate(
          merged(),
          const CommunityMemory.none(),
        );

        final hits = computed.insights.search.search('a1');
        expect(hits.first.id, 'a1');
        expect(hits.first.kind, MapSearchKind.topic);
        expect(
          computed.insights.communities.of(hits.first.communityId!),
          isNotNull,
        );
      },
    );

    test('las comunidades de hoy son las mismas con lo nuevo o sin él: lo '
        'nuevo no mueve el mapa', () {
      final input = merged();
      final withRecent = computeMap(input, const CommunityMemory.none());
      final withoutRecent = computeMap(
        TopicGraphInput(
          definitionId: input.definitionId,
          definitionName: input.definitionName,
          values: input.values,
          items: input.items,
          relations: input.relations,
        ),
        const CommunityMemory.none(),
      );

      expect(
        withRecent.detection.communityOf,
        withoutRecent.detection.communityOf,
      );
      expect(
        withRecent.detection.memory.nextId,
        withoutRecent.detection.memory.nextId,
      );
    });
  });

  group('con la bóveda grande del benchmark del mapa', () {
    /// Un árbol de dos mil temas, como el de la bóveda sintética: doce áreas
    /// de primer nivel y el resto colgando de otros ya puestos, con las ramas
    /// ricas haciéndose más ricas.
    TopicGraphInput tree() {
      final random = Random(3);
      final rows = <AtlasValueRow>[];
      for (var i = 0; i < 2000; i++) {
        final parent = i < 12
            ? null
            : rows[(pow(random.nextDouble(), 2) * rows.length).floor()].id;
        rows.add(AtlasValueRow(id: 't$i', label: 'Tema $i', parentId: parent));
      }
      return TopicGraphInput(
        definitionId: 'tema',
        definitionName: 'Tema',
        values: rows,
        items: const [],
        relations: const [],
      );
    }

    late TopicGraphInput input;
    late MapComputation computed;
    late TopicAdjacency adjacency;

    setUpAll(() {
      final structured = structuredTopicInput(tree(), now: now);
      input = TopicGraphInput(
        definitionId: structured.definitionId,
        definitionName: structured.definitionName,
        values: structured.values,
        items: structured.items,
        relations: structured.relations,
        // Quinientos sin tema, para que la burbuja pase su tope.
        unassigned: [
          for (var i = 0; i < 500; i++)
            TopicItem(
              id: 'suelto-$i',
              valueIds: const [],
              title: 'Suelto $i',
              createdAt: now.subtract(Duration(hours: i)),
            ),
        ],
        readAt: now,
      );
      computed = computeMap(input, const CommunityMemory.none());
      adjacency = TopicAdjacency.of(
        computed.graph,
        const TopicGraphWeights(),
        kHierarchyWeight,
      );
    });

    test('los puentes cuestan lo lineal: dos vueltas por las uniones y una '
        'más solo por las de los que se entregan', () {
      final bridges = computed.insights.bridges;

      var chosenDegree = 0;
      for (final bridge in bridges.bridges) {
        chosenDegree += adjacency.degreeOf(bridge.topic);
      }
      expect(bridges.visits, 2 * adjacency.neighbors.length + chosenDegree);
      expect(bridges.bridges, hasLength(kMaxBridges));
      expect(bridges.candidates, greaterThan(kMaxBridges));
      for (final bridge in bridges.bridges) {
        expect(bridge.joins, isNotEmpty);
        expect(bridge.joins.length, lessThanOrEqualTo(kMaxBridgeJoins));
        expect(
          bridge.communityId,
          computed.detection.communityOf[bridge.topic],
        );
        for (final join in bridge.joins) {
          expect(join.communityId, isNot(bridge.communityId));
          expect(computed.detection.communityById(join.communityId), isNotNull);
        }
      }
      // De más a menos.
      final scores = [for (final b in bridges.bridges) b.score];
      expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
    });

    test('una ficha por comunidad, con cada tema una sola vez y un nombre '
        'de a lo sumo dos temas', () {
      final profiles = computed.insights.communities;

      expect(profiles.all, hasLength(computed.detection.communities.length));
      final topics = [for (final p in profiles.all) ...p.topics];
      expect(topics, hasLength(computed.graph.nodes.length));
      expect(topics.toSet(), hasLength(computed.graph.nodes.length));
      for (final profile in profiles.all) {
        expect(profile.nameLabels, isNotEmpty);
        expect(profile.nameLabels.length, lessThanOrEqualTo(2));
        expect(profile.neighbors.length, lessThanOrEqualTo(5));
      }
    });

    test('el índice tiene cada tema y cada documento, cada uno en el lugar '
        'donde el mapa lo dibuja', () {
      final search = computed.insights.search;
      final graph = computed.graph;

      expect(
        search.entries,
        hasLength(
          graph.nodes.length + input.items.length + input.unassigned.length,
        ),
      );
      for (final item in input.items.take(500)) {
        final entry = search.document(item.id)!;
        final topic = graph.indexOf(entry.topicValueId!)!;
        expect(item.valueIds, contains(entry.topicValueId));
        expect(entry.communityId, computed.detection.communityOf[topic]);
      }
      final hits = search.search('documento 1234');
      expect(hits.first.id, 'e1234');
      expect(hits.length, lessThanOrEqualTo(kMapSearchResults));
    });

    test('la burbuja «Sin tema» dibuja como mucho su tope, los más nuevos', () {
      final bubble = computed.insights.unthemed;

      expect(bubble.count, 500);
      expect(bubble.items.items, hasLength(kMaxGraphItems));
      expect(bubble.items.items.first.id, 'suelto-0');
      expect(bubble.items.truncated, isTrue);
      expect(bubble.items.valueId, kUnthemedBubbleId);
    });

    test('lo nuevo: las ventanas se contienen, las listas tienen su tope y '
        'las cifras de hace un mes salen del grafo de entonces', () {
      final recent = computed.insights.recent;

      expect(recent.week.processedCount, greaterThan(0));
      expect(
        recent.week.processedCount,
        lessThanOrEqualTo(recent.month.processedCount),
      );
      expect(
        recent.week.linkedCount,
        lessThanOrEqualTo(recent.month.linkedCount),
      );
      expect(recent.month.processed, hasLength(kRecentListLength));
      expect(recent.month.linked, hasLength(kRecentListLength));
      final figures = recent.figures;
      expect(figures.documents.now, input.items.length + 500);
      expect(figures.documents.before, lessThan(figures.documents.now));
      expect(figures.links.before, lessThan(figures.links.now));
      // Los temas no tienen fecha en la bóveda del benchmark: de siempre.
      expect(figures.topics.delta, 0);
      expect(figures.communities.before, greaterThan(0));
    });
  });
}
