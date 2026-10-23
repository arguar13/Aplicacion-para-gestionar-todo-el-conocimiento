import 'package:sinapsis/features/map/domain/entities/topic_items.dart';

/// Lo que dibuja la vista «Vínculos» del Mapa (F28): los elementos y los
/// vínculos entre ellos, tengan o no temas o etiquetas.
///
/// No dibuja la bóveda entera: los elementos sin ningún vínculo no se dibujan
/// —no hay nada que mostrar de ellos acá— y, si los vinculados pasan de
/// [kMaxGraphItems], se queda con una parte (ver `selectLinkGraph`). Lo que
/// quedó afuera se cuenta, para decirlo.
class LinkGraph {
  const LinkGraph({
    required this.items,
    required this.edges,
    required this.linkedCount,
    required this.unlinkedCount,
    this.focusId,
    this.totalLinks = 0,
    this.shownLinks = 0,
  });

  const LinkGraph.empty({this.unlinkedCount = 0, this.focusId})
    : items = const [],
      edges = const [],
      linkedCount = 0,
      totalLinks = 0,
      shownLinks = 0;

  /// Los elementos que se dibujan.
  final List<TopicItemNode> items;

  /// Los vínculos con los DOS extremos en [items], por posición.
  final List<TopicItemEdge> edges;

  /// Cuántos elementos tienen algún vínculo, se dibujen o no.
  final int linkedCount;

  /// Cuántos elementos no tienen ningún vínculo: no se dibujan.
  final int unlinkedCount;

  /// El elemento en el que se pidió poner el foco, si está entre [items].
  final String? focusId;

  /// Cuántos vínculos hay entre los elementos que pasan el filtro, antes de
  /// quedarse con los más o los menos fuertes (F39, paso 8).
  final int totalLinks;

  /// Cuántos de [totalLinks] entran en lo que se pidió: todos, o la mitad más
  /// o menos fuerte. Con el tope de elementos, se dibujan los que caen en
  /// [items].
  final int shownLinks;

  /// Cuántos vinculados quedaron sin dibujar por el tope.
  int get hidden => linkedCount - items.length;
}
