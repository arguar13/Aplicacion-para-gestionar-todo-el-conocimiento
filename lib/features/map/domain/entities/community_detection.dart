import 'dart:typed_data';

/// Una comunidad de temas (F14): los que están más unidos entre sí que con el
/// resto. Sirve para colorear el mapa y para dibujar un solo nodo cuando el
/// zoom no alcanza a mostrar cada tema.
class TopicCommunity {
  const TopicCommunity({
    required this.id,
    required this.members,
    required this.anchor,
    required this.isIsolated,
  });

  /// La identidad de la comunidad. No cambia mientras la comunidad exista,
  /// aunque el cálculo se repita y se le sumen o quiten temas: es lo que hace
  /// que un color no salte de una comunidad a otra al recalcular.
  final int id;

  /// Las posiciones en `TopicGraph.nodes` de sus temas, de menor a mayor.
  final List<int> members;

  /// La posición del tema más unido a los demás de la comunidad: el que la
  /// nombra.
  final int anchor;

  /// Si es un tema solo, sin ninguna unión con otros.
  final bool isIsolated;
}

/// Lo que se recuerda de un cálculo para que el siguiente no parta de cero: a
/// qué comunidad pertenecía cada tema. Está indexado por el valor, no por su
/// posición, porque las posiciones cambian cuando aparece o desaparece un
/// tema.
///
/// Solo lleva números y textos: cruza sin problema al isolate del cálculo.
class CommunityMemory {
  const CommunityMemory({required this.byValueId, required this.nextId});

  /// Sin recuerdos: el primer cálculo, o el que se hace de cero.
  const CommunityMemory.none() : byValueId = const {}, nextId = 0;

  final Map<String, int> byValueId;

  /// La próxima identidad libre: mayor que todas las que se dieron alguna vez.
  final int nextId;
}

/// El resultado de agrupar un grafo de temas.
class CommunityDetection {
  const CommunityDetection({
    required this.communityOf,
    required this.communities,
    required this.memory,
    required this.passes,
    required this.converged,
    required this.reassigned,
  });

  /// El resultado de un grafo sin temas.
  CommunityDetection.empty(this.memory)
    : communityOf = Int32List(0),
      communities = const [],
      passes = 0,
      converged = true,
      reassigned = 0;

  /// La identidad de la comunidad de cada tema, por posición.
  final Int32List communityOf;

  /// Las comunidades, de la más grande a la más chica; a igual tamaño, por
  /// identidad.
  final List<TopicCommunity> communities;

  /// Lo que hay que pasarle al próximo cálculo para que las identidades se
  /// conserven.
  final CommunityMemory memory;

  /// Cuántas pasadas por los temas hicieron falta.
  final int passes;

  /// Si el cálculo se detuvo porque nada más cambiaba, y no por el tope de
  /// pasadas.
  final bool converged;

  /// Cuántos temas, de los que ya tenían comunidad, terminaron en otra. Cero en
  /// el primer cálculo: es lo que dice cuánto se movió el mapa tras un cambio.
  final int reassigned;

  /// La comunidad con esa identidad, o `null` si no existe.
  TopicCommunity? communityById(int id) {
    for (final community in communities) {
      if (community.id == id) return community;
    }
    return null;
  }
}
