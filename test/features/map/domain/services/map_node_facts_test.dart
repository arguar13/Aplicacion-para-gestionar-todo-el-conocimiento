import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/map_insights.dart';
import 'package:sinapsis/features/map/domain/entities/map_node_facts.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/services/canvas_tree_builder.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/map/domain/services/map_node_facts_builder.dart';

import 'insights_fixtures.dart';

/// Lo que dice la ficha de cada nodo del lienzo (F44, paso 4), con lo que el
/// lienzo ya tiene: el grafo, lo que sabe el motor y lo que se dibuja.
void main() {
  /// Roma, Grecia e Imperio muy unidos; Egipto y Nilo, aparte; Solo, sin
  /// ninguna unión. i0 —de Roma y Grecia— cita a i1 y se vincula con i12, de
  /// Egipto: las dos comunidades se unen. i17 no tiene tema; i18 es lo último
  /// que se procesó de la primera.
  final input = inputOf(
    ['egipto', 'grecia', 'imperio', 'nilo', 'roma', 'solo'],
    [
      ...repeat(4, ['roma', 'grecia']),
      ...repeat(4, ['grecia', 'imperio']),
      ...repeat(4, ['roma', 'imperio']),
      ...repeat(4, ['egipto', 'nilo']),
      ['solo'],
      [],
      ['roma'],
    ],
    relations: const [
      TopicRelation(fromItemId: 'i0', toItemId: 'i1', kind: RelationKind.cites),
      TopicRelation(
        fromItemId: 'i0',
        toItemId: 'i12',
        kind: RelationKind.relatedTo,
      ),
    ],
    itemDates: {
      'i0': DateTime(2026, 10),
      'i12': DateTime(2026, 10, 2),
      'i18': DateTime(2026, 10, 20),
    },
    readAt: DateTime(2026, 10, 25),
  );
  final computed = computeMap(input, const CommunityMemory.none());
  final graph = computed.graph;
  final detection = computed.detection;
  final insights = computed.insights;
  final overview = aggregateCommunities(graph, detection);

  int overviewOf(String valueId) => overview.nodes.indexWhere(
    (node) => node.members.contains(graph.indexOf(valueId)),
  );

  MapNodeFacts? factsOf(
    MapNodeRef ref, {
    GraphScene scene = const GraphScene.empty(),
    CanvasTree? tree,
    MapInsights? withInsights,
  }) => mapNodeFacts(
    ref,
    graph: graph,
    detection: detection,
    overview: overview,
    insights: withInsights ?? insights,
    scene: scene,
    tree: tree,
  );

  group('una comunidad', () {
    test('su nombre, todos sus temas, sus documentos y vínculos, con quién se '
        'une y lo más reciente', () {
      final at = overviewOf('roma');
      final facts = factsOf(MapCommunityRef(at))!;
      final id = overview.nodes[at].communityIds.first;
      final profile = insights.communities.of(id)!;

      expect(facts.kind, MapNodeKind.community);
      expect(facts.title, profile.name);
      expect(facts.title, contains(' · '));
      expect(facts.nameLabels, profile.nameLabels);
      expect(facts.group, id);
      expect(facts.topicNames.toSet(), {'Roma', 'Grecia', 'Imperio'});
      expect(facts.topicCount, 3);
      // Doce de a dos temas y el último, de Roma sola.
      expect(facts.documentCount, 13);
      // i0 cita a i1, los dos adentro; el vínculo con i12 sale de ella.
      expect(facts.linkCount, 1);

      final egipto = overviewOf('egipto');
      final other = insights.communities.of(
        overview.nodes[egipto].communityIds.first,
      )!;
      expect(facts.neighbors, [
        MapNodeNeighbor(
          ref: MapCommunityRef(egipto),
          label: other.name,
          shortLabel: other.nameLabels.first,
        ),
      ]);
      expect(
        facts.latest,
        const MapNodeNeighbor(
          ref: MapDocumentRef('i18'),
          label: 'Documento 18',
        ),
      );
      expect(facts.canEnter, isTrue);
      expect(facts.isDocument, isFalse);
    });

    test('sin lo que calcula el motor: su tema más unido y cuántos temas '
        'junta', () {
      final at = overviewOf('roma');
      final facts = factsOf(
        MapCommunityRef(at),
        withInsights: const MapInsights.empty(),
      )!;
      final anchor = overview.nodes[at].anchor!;

      expect(facts.title, graph.nodes[anchor].label);
      expect(facts.nameLabels, [graph.nodes[anchor].label]);
      expect(facts.topicCount, 3);
      expect(facts.documentCount, isNull);
      expect(facts.linkCount, isNull);
      expect(facts.neighbors, isEmpty);
      expect(facts.latest, isNull);
    });

    test(
      'lo que junta varias —los aislados— es un grupo, con cuántos temas',
      () {
        final at = overview.nodes.indexWhere(
          (node) => node.kind == OverviewKind.isolated,
        );
        final facts = factsOf(MapCommunityRef(at))!;

        expect(facts.kind, MapNodeKind.group);
        expect(facts.title, isEmpty);
        expect(facts.topicCount, 1);
        expect(facts.neighbors, isEmpty);
      },
    );

    test('una que no está en el panorama no tiene ficha', () {
      expect(factsOf(MapCommunityRef(overview.nodes.length)), isNull);
      expect(factsOf(const MapCommunityRef(-1)), isNull);
    });
  });

  group('un tema', () {
    test('sus documentos, con cuántos se une, los más unidos primero y su '
        'comunidad', () {
      final facts = factsOf(const MapTopicRef('roma'))!;
      final community = detection.communityOf[graph.indexOf('roma')!];

      expect(facts.kind, MapNodeKind.topic);
      expect(facts.title, 'Roma');
      expect(facts.documentCount, 9);
      // Grecia e Imperio por lo que comparten —Grecia, además, por la cita—;
      // Egipto y Nilo por el vínculo de i0, y entre ellos dos, por nombre.
      expect(facts.topicCount, 4);
      expect(
        [for (final n in facts.neighbors) n.label],
        ['Grecia', 'Imperio', 'Egipto'],
      );
      expect(facts.neighbors.first.ref, const MapTopicRef('grecia'));
      expect(facts.within, insights.communities.of(community)!.name);
      expect(facts.group, community);
    });

    test('uno sin uniones no tiene vecinos', () {
      final facts = factsOf(const MapTopicRef('solo'))!;

      expect(facts.topicCount, 0);
      expect(facts.neighbors, isEmpty);
    });

    test('uno que no existe no tiene ficha', () {
      expect(factsOf(const MapTopicRef('atlantida')), isNull);
    });
  });

  group('un documento', () {
    /// i0 contradice a i1 y cita a i12; i12 no tiene más.
    final scene = sceneOfItems(
      const TopicItemsGraph(
        valueId: 'roma',
        items: [
          TopicItemNode(id: 'i0', title: 'Livio', isNote: false),
          TopicItemNode(id: 'i1', title: 'Mi nota', isNote: true),
          TopicItemNode(id: 'i12', title: 'Heródoto', isNote: false),
        ],
        edges: [
          TopicItemEdge(a: 0, b: 2, kind: RelationKind.cites),
          TopicItemEdge(a: 0, b: 1, kind: RelationKind.contradicts),
        ],
        truncated: false,
      ),
    );

    test('dibujado: con qué se lo ve vinculado, lo que más une primero, y por '
        'qué tema se llega a él', () {
      final facts = factsOf(const MapDocumentRef('i0'), scene: scene)!;
      final place = insights.search.document('i0')!.topicValueId!;

      expect(facts.kind, MapNodeKind.source);
      expect(facts.title, 'Livio');
      expect(facts.linkCount, 2);
      // Una contradicción une más que una cita.
      expect(facts.neighbors, const [
        MapNodeNeighbor(ref: MapDocumentRef('i1'), label: 'Mi nota'),
        MapNodeNeighbor(ref: MapDocumentRef('i12'), label: 'Heródoto'),
      ]);
      expect(facts.place?.ref, MapTopicRef(place));
      expect(facts.place?.label, graph.nodes[graph.indexOf(place)!].label);
      expect(facts.isDocument, isTrue);
      expect(facts.canEnter, isFalse);
    });

    test('una nota dibujada es una nota', () {
      final facts = factsOf(const MapDocumentRef('i1'), scene: scene)!;

      expect(facts.kind, MapNodeKind.note);
      expect(facts.neighbors.single.ref, const MapDocumentRef('i0'));
    });

    test('sin dibujar: su nombre sale del índice, sin vínculos que contar', () {
      final facts = factsOf(const MapDocumentRef('i18'))!;

      expect(facts.title, 'Documento 18');
      expect(facts.linkCount, isNull);
      expect(facts.neighbors, isEmpty);
      expect(facts.place?.ref, const MapTopicRef('roma'));
    });

    test('solo en el árbol: con qué se lo ve vinculado ahí, por vínculo y no '
        'por nota mapa', () {
      // x0 cita a x1, que se vincula con x2; m1 es una nota mapa de x0. Ninguno
      // está en el índice: solo los trajo el árbol.
      final tree = buildCanvasTree(
        root: const CanvasTreeRef.item('x0'),
        rootTitle: 'Livio',
        graph: graph,
        expanded: const {'item:x0', 'item:x1'},
        links: const {
          'item:x0': [
            CanvasTreeLink(
              target: CanvasTreeRef.item('x1'),
              title: 'Heródoto',
              edge: CanvasTreeEdge.relation,
              relation: RelationKind.cites,
            ),
            CanvasTreeLink(
              target: CanvasTreeRef.item('m1'),
              title: 'Mapa de Roma',
              edge: CanvasTreeEdge.mapNote,
              isNote: true,
            ),
          ],
          'item:x1': [
            CanvasTreeLink(
              target: CanvasTreeRef.item('x2'),
              title: 'Tucídides',
              edge: CanvasTreeEdge.relation,
              relation: RelationKind.relatedTo,
            ),
          ],
        },
      );

      final middle = factsOf(const MapDocumentRef('x1'), tree: tree)!;
      expect(middle.title, 'Heródoto');
      expect(middle.kind, MapNodeKind.source);
      expect(middle.linkCount, 2);
      expect(middle.neighbors, const [
        MapNodeNeighbor(ref: MapDocumentRef('x0'), label: 'Livio'),
        MapNodeNeighbor(ref: MapDocumentRef('x2'), label: 'Tucídides'),
      ]);
      expect(middle.place, isNull);

      final root = factsOf(const MapDocumentRef('x0'), tree: tree)!;
      expect(root.linkCount, 1);
      expect(root.neighbors.single.ref, const MapDocumentRef('x1'));

      final note = factsOf(const MapDocumentRef('m1'), tree: tree)!;
      expect(note.kind, MapNodeKind.note);
      expect(note.linkCount, 0);
    });

    test('sin tema no tiene adónde volar; sin estar en ninguna parte, no '
        'tiene ficha', () {
      expect(factsOf(const MapDocumentRef('i17'))!.place, isNull);
      expect(factsOf(const MapDocumentRef('nada')), isNull);
    });
  });

  test('lo recordado: la misma ficha con lo mismo no se vuelve a armar; con '
      'otra escena, sí', () {
    final memo = MapNodeFactsMemo();
    MapNodeFacts? recall(GraphScene scene) => memo.of(
      const MapTopicRef('roma'),
      graph: graph,
      detection: detection,
      overview: overview,
      insights: insights,
      scene: scene,
    );
    const scene = GraphScene.empty();
    final first = recall(scene);

    expect(identical(recall(scene), first), isTrue);
    final other = recall(sceneOfItems(const TopicItemsGraph.empty('roma')));
    expect(identical(other, first), isFalse);
    expect(other!.title, first!.title);
  });

  group('lo que es cada nodo de la escena', () {
    test('una comunidad, un tema o un documento, ida y vuelta', () {
      for (final ref in const [
        MapCommunityRef(3),
        MapTopicRef('roma'),
        MapDocumentRef('i:1'),
      ]) {
        expect(MapNodeRef.ofSceneKey(ref.sceneKey), ref);
      }
    });

    test('lo que no es ninguno, no es nada', () {
      for (final key in ['', 'overview:', 'overview:x', 'topic', 'otro:1']) {
        expect(MapNodeRef.ofSceneKey(key), isNull, reason: key);
      }
    });
  });
}
