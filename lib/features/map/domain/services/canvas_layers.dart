import 'package:sinapsis/features/map/domain/entities/map_layers.dart';
import 'package:sinapsis/features/map/domain/entities/unthemed_bubble.dart';
import 'package:sinapsis/features/map/domain/services/graph_scene.dart';
import 'package:sinapsis/features/map/domain/services/level_of_detail.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// La clave de la burbuja «Sin tema» en la escena de lejos.
const kUnthemedSceneKey = 'unthemed';

/// La escena de lejos con la burbuja «Sin tema» (F44, paso 5): un nodo gris
/// más, del tamaño de sus documentos, unido a las comunidades con las que se
/// vinculan —por la cantidad de vínculos—. Sin documentos sin tema, la escena
/// tal cual.
///
/// La burbuja entra siempre en lo que se acomoda, esté prendida o no su capa:
/// prenderla después solo la deja ver ([layeredScene]), sin volver a
/// acomodar nada. Un vínculo con una comunidad que de lejos va junto con otras
/// —el desborde— suma a ese nodo.
GraphScene sceneWithUnthemed(
  GraphScene scene,
  CommunityOverview overview,
  UnthemedBubble bubble,
) {
  if (bubble.isEmpty) return scene;
  final nodeOf = <int, int>{
    for (var i = 0; i < overview.nodes.length; i++)
      for (final id in overview.nodes[i].communityIds) id: i,
  };
  final weights = <int, double>{};
  for (final link in bubble.communities) {
    final at = nodeOf[link.communityId];
    if (at != null)
      weights.update(at, (w) => w + link.weight, ifAbsent: () => link.weight);
  }
  final bubbleAt = scene.nodes.length;
  return GraphScene(
    nodes: [
      ...scene.nodes,
      SceneNode(
        key: kUnthemedSceneKey,
        kind: SceneKind.unthemed,
        label: '',
        size: bubble.count,
        count: bubble.count,
      ),
    ],
    edges: [
      ...scene.edges,
      for (final at in weights.keys.toList()..sort())
        SceneEdge(a: at, b: bubbleAt, weight: weights[at]!),
    ],
    hidden: scene.hidden,
    hiddenEdges: scene.hiddenEdges,
  );
}

/// Lo que se dibuja de [laidOut] —lo que se acomodó— con las capas [layers]
/// prendidas (F44, paso 5). Es un recorte: los nodos y las uniones que quedan,
/// en el mismo orden, con las posiciones de las uniones vueltas a contar.
///
/// - Sin **«Sin tema»**, la burbuja gris no está, ni sus uniones.
/// - Sin **«Vínculos»**, no están las uniones entre documentos; con
///   **«Contradicciones»**, las que contradicen se quedan.
/// - Sin **«Contradicciones»**, una unión en tensión se dibuja como las demás:
///   acá deja de estar marcada (`SceneEdge.tension`), y el dibujo la pinta con
///   el color de siempre y sin su rayo.
///
/// Las uniones entre comunidades y entre temas no dependen de ninguna capa. No
/// acomoda nada: las posiciones son por clave, y las de [laidOut] sirven tal
/// cual. Lineal en lo dibujado.
GraphScene layeredScene(GraphScene laidOut, Set<MapLayer> layers) {
  final unthemed = layers.contains(MapLayer.unthemed);
  final links = layers.contains(MapLayer.links);
  final tensions = layers.contains(MapLayer.tensions);

  final positionOf = List<int>.filled(laidOut.nodes.length, -1);
  final nodes = <SceneNode>[];
  for (var i = 0; i < laidOut.nodes.length; i++) {
    final node = laidOut.nodes[i];
    if (!unthemed && node.kind == SceneKind.unthemed) continue;
    positionOf[i] = nodes.length;
    nodes.add(node);
  }

  final edges = <SceneEdge>[];
  for (final edge in laidOut.edges) {
    final a = positionOf[edge.a];
    final b = positionOf[edge.b];
    if (a < 0 || b < 0) continue;
    final betweenDocuments = edge.relation != null;
    if (betweenDocuments && !links && !(tensions && edge.tension)) continue;
    final tension = tensions && edge.tension;
    edges.add(
      a == edge.a && b == edge.b && tension == edge.tension
          ? edge
          : SceneEdge(
              a: a,
              b: b,
              weight: edge.weight,
              tension: tension,
              relation: edge.relation,
            ),
    );
  }
  return GraphScene(
    nodes: nodes,
    edges: edges,
    hidden: laidOut.hidden,
    hiddenEdges: laidOut.hiddenEdges,
  );
}

/// Los documentos de [scene], por identificador: entre ellos busca
/// «Parecidos».
List<String> sceneDocuments(GraphScene scene) => [
  for (final node in scene.nodes)
    if (node.kind == SceneKind.note || node.kind == SceneKind.source)
      if (node.ref case final id?) id,
];

/// Cuántas uniones en tensión se dibujan en [scene]: lo que dice la capa
/// «Contradicciones» de lo que está a la vista.
int tensionCount(GraphScene scene) =>
    scene.edges.where((edge) => edge.tension).length;

/// Una propuesta de «Parecidos» como se dibuja: el par y sus dos extremos en
/// la escena.
typedef MapSimilarLine = ({SimilarPair pair, int a, int b});

/// Las propuestas de [pairs] que se dibujan en [visible]: las de dos
/// documentos a la vista que no están vinculados en [laidOut] —con su capa
/// prendida o no—. Un vínculo recién hecho saca a su par en el acto, antes de
/// que se vuelva a comparar nada.
List<MapSimilarLine> similarLines(
  GraphScene visible,
  GraphScene laidOut,
  List<SimilarPair> pairs,
) {
  if (pairs.isEmpty) return const [];
  final at = <String, int>{
    for (var i = 0; i < visible.nodes.length; i++)
      if (visible.nodes[i].ref case final id?)
        if (visible.nodes[i].kind == SceneKind.note ||
            visible.nodes[i].kind == SceneKind.source)
          id: i,
  };
  final linked = <String>{
    for (final edge in laidOut.edges)
      if (edge.relation != null)
        if (laidOut.nodes[edge.a].ref case final a?)
          if (laidOut.nodes[edge.b].ref case final b?) similarPairKey(a, b),
  };
  return [
    for (final pair in pairs)
      if (at[pair.a] case final a?)
        if (at[pair.b] case final b?)
          if (!linked.contains(pair.key)) (pair: pair, a: a, b: b),
  ];
}
