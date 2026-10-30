import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/map_bridges.dart';
import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';
import 'package:sinapsis/features/map/domain/services/board_facts.dart';
import 'package:sinapsis/features/map/domain/services/canvas_layers.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// Las capas del lienzo del Mapa (F44, paso 5), en el dominio: qué se acomoda,
/// qué se dibuja con cada capa y qué parecidos quedan a la vista. Nada de esto
/// acomoda ni lee: recorta lo que ya está.
void main() {
  SceneNode community(int i) => SceneNode(
    key: 'overview:$i',
    kind: SceneKind.community,
    label: 'C$i',
    size: 10,
    group: i,
  );
  SceneNode document(String id) => SceneNode(
    key: 'item:$id',
    kind: SceneKind.source,
    label: id,
    size: 1,
    ref: id,
  );

  OverviewNode overviewNode(List<int> ids, OverviewKind kind) => OverviewNode(
    kind: kind,
    communityIds: ids,
    members: const [],
    anchor: null,
    itemCount: 10,
    internalWeight: 1,
  );

  /// De lejos: dos comunidades unidas por algo que contradice, y un desborde
  /// con las comunidades 7 y 8.
  final overview = CommunityOverview(
    nodes: [
      overviewNode([3], OverviewKind.community),
      overviewNode([5], OverviewKind.community),
      overviewNode([7, 8], OverviewKind.overflow),
    ],
    edges: const [],
  );
  final far = GraphScene(
    nodes: [community(0), community(1), community(2)],
    edges: const [SceneEdge(a: 0, b: 1, weight: 4, tension: true)],
  );

  UnthemedBubble bubble(List<CommunityLink> communities, {int count = 7}) =>
      UnthemedBubble(
        count: count,
        items: const TopicItemsGraph(
          valueId: kUnthemedBubbleId,
          items: [TopicItemNode(id: 's1', title: 'Suelto', isNote: false)],
          edges: [],
          truncated: false,
        ),
        communities: communities,
        linkedCount: 1,
      );

  group('la burbuja «Sin tema» entre las comunidades', () {
    test('un nodo gris más, del tamaño de sus documentos, unido a las '
        'comunidades con las que se vincula —el desborde suma las suyas—', () {
      final scene = sceneWithUnthemed(
        far,
        overview,
        bubble(const [
          CommunityLink(communityId: 5, weight: 3),
          CommunityLink(communityId: 8, weight: 2),
          CommunityLink(communityId: 7, weight: 1),
          // Una que de lejos no está: no une con nada.
          CommunityLink(communityId: 99, weight: 9),
        ]),
      );

      expect(scene.nodes, hasLength(4));
      final node = scene.nodes.last;
      expect(node.key, kUnthemedSceneKey);
      expect(node.kind, SceneKind.unthemed);
      expect((node.size, node.count), (7, 7));
      expect(scene.edges, hasLength(3));
      expect(
        [for (final e in scene.edges.skip(1)) (e.a, e.b, e.weight)],
        [(1, 3, 3.0), (2, 3, 3.0)],
      );
    });

    test('sin documentos sin tema, la escena tal cual', () {
      expect(
        sceneWithUnthemed(far, overview, const UnthemedBubble.empty()),
        same(far),
      );
    });
  });

  group('lo que se dibuja con cada capa', () {
    final laidOut = sceneWithUnthemed(
      far,
      overview,
      bubble(const [CommunityLink(communityId: 3, weight: 2)]),
    );

    test(
      'sin «Sin tema», la burbuja no está, ni sus uniones; con ella, sí',
      () {
        final off = layeredScene(laidOut, const {});
        expect(off.nodes.map((n) => n.key), isNot(contains(kUnthemedSceneKey)));
        expect(off.edges, hasLength(1));

        final on = layeredScene(laidOut, const {MapLayer.unthemed});
        expect(on.nodes.last.key, kUnthemedSceneKey);
        expect(on.edges, hasLength(2));
      },
    );

    test('sin «Contradicciones», una unión en tensión se dibuja como las '
        'demás; con ella, marcada', () {
      expect(layeredScene(laidOut, const {}).edges.first.tension, isFalse);
      expect(
        layeredScene(laidOut, const {MapLayer.tensions}).edges.first.tension,
        isTrue,
      );
    });

    final documents = GraphScene(
      nodes: [document('a'), document('b'), document('c')],
      edges: const [
        SceneEdge(
          a: 0,
          b: 1,
          weight: 3,
          tension: true,
          relation: RelationKind.contradicts,
        ),
        SceneEdge(a: 1, b: 2, weight: 2, relation: RelationKind.cites),
      ],
      hidden: 4,
    );

    test('sin «Vínculos», no están las uniones entre documentos, salvo las que '
        'contradicen con «Contradicciones»', () {
      expect(layeredScene(documents, const {}).edges, isEmpty);
      final tensions = layeredScene(documents, const {MapLayer.tensions});
      expect(
        [for (final e in tensions.edges) e.relation],
        [RelationKind.contradicts],
      );
      final links = layeredScene(documents, const {MapLayer.links});
      expect(links.edges, hasLength(2));
      // Lo que no se dibujó por el tope se sigue contando.
      expect(links.hidden, 4);
    });

    test(
      'las posiciones de las uniones se vuelven a contar sin la burbuja',
      () {
        final scene = GraphScene(
          nodes: [
            community(0),
            const SceneNode(
              key: kUnthemedSceneKey,
              kind: SceneKind.unthemed,
              label: '',
              size: 2,
            ),
            community(1),
          ],
          edges: const [SceneEdge(a: 0, b: 2, weight: 1)],
        );
        final shown = layeredScene(scene, const {});
        expect((shown.edges.single.a, shown.edges.single.b), (0, 1));
      },
    );
  });

  group('los parecidos a la vista', () {
    final laidOut = GraphScene(
      nodes: [document('a'), document('b'), document('c'), document('d')],
      edges: const [
        SceneEdge(a: 0, b: 1, weight: 2, relation: RelationKind.cites),
      ],
    );

    test('solo entre dos documentos dibujados, y nunca los ya vinculados, '
        'aunque «Vínculos» no los dibuje', () {
      final visible = layeredScene(laidOut, const {});
      final lines = similarLines(visible, laidOut, [
        SimilarPair('b', 'a', 0.9),
        SimilarPair('c', 'd', 0.8),
        SimilarPair('a', 'fuera', 0.95),
      ]);

      expect(lines, hasLength(1));
      expect((lines.single.pair.a, lines.single.pair.b), ('c', 'd'));
      expect((lines.single.a, lines.single.b), (2, 3));
    });

    test('los documentos de la escena, por identificador', () {
      expect(sceneDocuments(laidOut), ['a', 'b', 'c', 'd']);
      expect(sceneDocuments(far), isEmpty);
    });
  });

  test('cuántas contradicciones se ven', () {
    expect(tensionCount(layeredScene(far, const {MapLayer.tensions})), 1);
    expect(tensionCount(layeredScene(far, const {})), 0);
  });

  test('el estudio de un documento: sin tarjetas, para hoy o al día', () {
    expect(MapStudyMark.of(null), const MapStudyMark(MapStudyState.none));
    expect(
      MapStudyMark.of(const BoardCardFact(cards: 0, dueToday: 0)),
      const MapStudyMark(MapStudyState.none),
    );
    expect(
      MapStudyMark.of(const BoardCardFact(cards: 5, dueToday: 3)),
      const MapStudyMark(MapStudyState.due, due: 3),
    );
    expect(
      MapStudyMark.of(const BoardCardFact(cards: 5, dueToday: 0)),
      const MapStudyMark(MapStudyState.upToDate),
    );
  });

  test('las capas arrancan apagadas, salvo «Vínculos» (decisión B)', () {
    expect(kDefaultMapLayers, {MapLayer.links});
  });
}
