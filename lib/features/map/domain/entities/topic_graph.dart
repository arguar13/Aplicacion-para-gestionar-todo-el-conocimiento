import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart'
    show AtlasValueRow;

/// Un tema del mapa de conocimiento (F14): un valor de la categoría que se
/// está mirando, con su lugar en la jerarquía de F13.
class TopicNode {
  const TopicNode({
    required this.valueId,
    required this.label,
    required this.depth,
    required this.itemCount,
    this.parentId,
  });

  final String valueId;
  final String label;

  /// El valor del que cuelga, o `null` si es del primer nivel.
  final String? parentId;

  /// El nivel en la jerarquía: 0 para el primer nivel.
  final int depth;

  /// Cuántos elementos vivos lo tienen asignado DIRECTAMENTE, sin contar los
  /// de sus subtemas: el tamaño del nodo.
  final int itemCount;
}

/// La unión entre dos temas: lo que los relaciona, contado, sin decidir todavía
/// cuánto pesa.
///
/// Es una arista NO dirigida: [a] y [b] son posiciones en `TopicGraph.nodes`, y
/// siempre `a < b`. Una relación de un elemento del tema X a uno del tema Y y
/// otra de Y a X suman en la misma arista.
class TopicEdge {
  const TopicEdge({
    required this.a,
    required this.b,
    required this.cooccurrence,
    required this.relations,
    required this.contradictions,
    required this.openContradictions,
  });

  final int a;
  final int b;

  /// En cuántos elementos aparecen los dos temas a la vez.
  final int cooccurrence;

  /// Cuántas relaciones entre un elemento de un tema y uno del otro, de
  /// cualquier tipo menos `contradicts`.
  final int relations;

  /// Cuántas relaciones `contradicts` hay entre los dos temas.
  final int contradictions;

  /// De esas, las que nadie revisó todavía.
  final int openContradictions;

  /// Si entre estos dos temas hay una tensión. La tensión es información y no
  /// ruido: la arista se marca, no solo pesa más.
  bool get isTension => contradictions > 0;
}

/// Cuánto vale cada cosa que une a dos temas (F14, D2).
///
/// Una relación `contradicts` pesa MÁS que una común: dos temas que se
/// contradicen están más juntos, para quien quiere entender el dominio, que
/// dos que solo comparten un elemento.
class TopicGraphWeights {
  const TopicGraphWeights({
    this.cooccurrence = 1,
    this.relation = 2,
    this.contradiction = 3,
  });

  final double cooccurrence;
  final double relation;
  final double contradiction;

  /// Lo que pesa la arista [edge].
  double of(TopicEdge edge) =>
      edge.cooccurrence * cooccurrence +
      edge.relations * relation +
      edge.contradictions * contradiction;
}

/// El grafo de temas de UNA categoría (F14): sus valores como nodos y, como
/// aristas, todo lo que los une —elementos que comparten, relaciones entre sus
/// elementos, contradicciones—.
///
/// Es un derivado: se calcula de las asignaciones y de las relaciones y no se
/// guarda; si falla, ninguna otra pantalla lo nota.
class TopicGraph {
  TopicGraph({
    required this.definitionId,
    required this.definitionName,
    required this.nodes,
    required this.edges,
  });

  /// El grafo de una categoría sin valores, o que no existe.
  factory TopicGraph.empty(String definitionId, {String name = ''}) =>
      TopicGraph(
        definitionId: definitionId,
        definitionName: name,
        nodes: const [],
        edges: const [],
      );

  final String definitionId;
  final String definitionName;

  /// Los temas, por nombre sin acentos ni mayúsculas: un orden que no depende
  /// de cómo los devolvió la base.
  final List<TopicNode> nodes;

  /// Las uniones entre temas, por posición de sus extremos: también en un orden
  /// que no depende de la base.
  final List<TopicEdge> edges;

  late final Map<String, int> _index = {
    for (var i = 0; i < nodes.length; i++) nodes[i].valueId: i,
  };

  /// La posición del tema con ese valor, o `null` si no está.
  int? indexOf(String valueId) => _index[valueId];
}

/// Un elemento con los valores de la categoría que tiene: lo que hace falta
/// para contar qué temas aparecen juntos.
class TopicItem {
  const TopicItem({required this.id, required this.valueIds});

  final String id;
  final List<String> valueIds;
}

/// Una relación entre dos elementos, con lo justo para pesarla.
class TopicRelation {
  const TopicRelation({
    required this.fromItemId,
    required this.toItemId,
    required this.kind,
    this.reviewed = false,
  });

  final String fromItemId;
  final String toItemId;
  final RelationKind kind;

  /// Si alguien la revisó: solo importa para las contradicciones.
  final bool reviewed;
}

/// Lo que hace falta para armar un [TopicGraph]: lo que la base entrega, sin
/// contar todavía.
///
/// Solo lleva textos, números y listas: cruza sin problema al isolate que
/// calcula el mapa.
class TopicGraphInput {
  const TopicGraphInput({
    required this.definitionId,
    required this.definitionName,
    required this.values,
    required this.items,
    required this.relations,
    this.unassignedItemIds = const [],
  });

  /// La entrada de una categoría que no existe o que no tiene valores.
  const TopicGraphInput.empty(this.definitionId, {this.definitionName = ''})
    : values = const [],
      items = const [],
      relations = const [],
      unassignedItemIds = const [];

  final String definitionId;
  final String definitionName;

  /// Todos los valores de la categoría, tengan o no elementos.
  final List<AtlasValueRow> values;

  /// Los elementos vivos que pasan el filtro y tienen algún valor.
  final List<TopicItem> items;

  /// Las relaciones cuyos DOS extremos son elementos de [items].
  final List<TopicRelation> relations;

  /// Los elementos vivos que pasan el filtro y NO tienen ningún valor: no
  /// entran en el grafo, y el Mapa dice cuántos son en vez de callarlos
  /// (F28).
  final List<String> unassignedItemIds;
}
