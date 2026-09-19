import 'package:sinapsis/core/domain/entities/relation_edge.dart';

/// Lo que rodea a un elemento en el grafo: quiénes son sus vecinos hasta cierta
/// cantidad de saltos y los vínculos que hay entre todos ellos.
///
/// Es un recorte del grafo y no el grafo entero a propósito: el panel del
/// detalle y el grafo local solo dibujan lo cercano, y pedir cada elemento y
/// cada vínculo de la bóveda para quedarse con unos pocos era lo que tardaba un
/// minuto con diez mil elementos.
class Neighborhood {
  const Neighborhood({
    required this.nodeIds,
    required this.edges,
    this.omitted = 0,
  });

  /// Sin vecinos: el elemento no existe o no tiene ningún vínculo.
  static const empty = Neighborhood(nodeIds: {}, edges: []);

  /// El elemento de partida y sus vecinos, sin repetir.
  final Set<String> nodeIds;

  /// Todos los vínculos que hay entre [nodeIds], y solo esos.
  final List<RelationEdge> edges;

  /// Cuántos vecinos quedaron fuera por el tope de nodos. Un elemento muy
  /// conectado tiene cientos, y dibujarlos todos no ayuda a nadie: entran los
  /// vinculados más recientemente y esto dice cuántos faltan, para que lo que
  /// se ve no pase por completo cuando no lo es.
  final int omitted;

  bool get isTruncated => omitted > 0;
}
