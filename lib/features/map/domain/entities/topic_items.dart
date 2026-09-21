import 'package:sinapsis/core/domain/entities/relation_kind.dart';

/// Cuántos elementos dibuja el mapa, como máximo, al acercarse a un tema (F14,
/// D5): el mismo tope del grafo local del detalle.
const kMaxGraphItems = 200;

/// Un elemento del nivel más cercano del mapa.
class TopicItemNode {
  const TopicItemNode({
    required this.id,
    required this.title,
    required this.isNote,
  });

  final String id;
  final String title;

  /// Si es una nota; si no, es una fuente.
  final bool isNote;
}

/// Un vínculo entre dos elementos del nivel más cercano.
class TopicItemEdge {
  const TopicItemEdge({required this.a, required this.b, required this.kind});

  /// Posiciones en `TopicItemsGraph.items`; el vínculo va de [a] a [b].
  final int a;
  final int b;
  final RelationKind kind;
}

/// Los elementos de un tema y de sus subtemas, con los vínculos entre ellos: lo
/// que se dibuja al acercarse a un tema.
class TopicItemsGraph {
  const TopicItemsGraph({
    required this.valueId,
    required this.items,
    required this.edges,
    required this.truncated,
  });

  const TopicItemsGraph.empty(this.valueId)
    : items = const [],
      edges = const [],
      truncated = false;

  final String valueId;

  /// Los elementos vivos, los tocados más recientemente primero.
  final List<TopicItemNode> items;

  /// Los vínculos con los DOS extremos en [items].
  final List<TopicItemEdge> edges;

  /// Si el tema tiene más elementos que [kMaxGraphItems].
  final bool truncated;
}
