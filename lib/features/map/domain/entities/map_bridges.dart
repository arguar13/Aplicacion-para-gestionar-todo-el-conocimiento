/// Lo que une a una comunidad con otra: la suma de las uniones entre sus temas.
class CommunityLink {
  const CommunityLink({required this.communityId, required this.weight});

  /// La identidad de la otra comunidad.
  final int communityId;

  /// Lo que suman las uniones, con el mismo peso que las comunidades (F14,
  /// D2) y la jerarquía.
  final double weight;
}

/// Lo que un puente une con UNA de las otras comunidades.
class BridgeJoin {
  const BridgeJoin({
    required this.communityId,
    required this.weight,
    required this.share,
  });

  /// La identidad de la otra comunidad.
  final int communityId;

  /// Lo que pesan las uniones del puente con los temas de esa comunidad.
  final double weight;

  /// Qué parte de todo lo que une a las dos comunidades pasa por el puente,
  /// de 0 a 1.
  final double share;

  /// Si es la ÚNICA unión directa entre su comunidad y esa: sin él, las dos
  /// quedarían sueltas, o unidas solo a través de una tercera.
  bool get isSole => share >= 1;
}

/// Un tema que une comunidades distintas (F44): el que, si se sacara, dejaría
/// partes del mapa más sueltas.
class TopicBridge {
  const TopicBridge({
    required this.topic,
    required this.communityId,
    required this.score,
    required this.joins,
    required this.joinedCount,
    required this.soleCount,
  });

  /// La posición del tema en `TopicGraph.nodes`.
  final int topic;

  /// La identidad de su comunidad.
  final int communityId;

  /// Cuánto une: lo que pesa cada unión con otra comunidad, multiplicado por
  /// la parte que el puente lleva de todo lo que une a las dos. Un tema que es
  /// la única unión entre dos comunidades vale todo su peso; uno de cien
  /// caminos parecidos, casi nada.
  final double score;

  /// Las otras comunidades que une, de la que más pesa a la que menos, como
  /// mucho `kMaxBridgeJoins`.
  final List<BridgeJoin> joins;

  /// Con cuántas otras comunidades se une, en total.
  final int joinedCount;

  /// De cuántas es la única unión directa con su comunidad.
  final int soleCount;
}

/// Los puentes de un mapa, de los que más unen a los que menos.
class BridgeAnalysis {
  const BridgeAnalysis({
    required this.bridges,
    required this.topics,
    required this.candidates,
    required this.visits,
  });

  /// Un mapa sin puentes.
  const BridgeAnalysis.empty()
    : bridges = const [],
      topics = const {},
      candidates = 0,
      visits = 0;

  /// Los que más unen, como mucho `kMaxBridges`: los que se marcan con el
  /// anillo doble y los que lista el Resumen.
  final List<TopicBridge> bridges;

  /// Las posiciones de los temas de [bridges], para preguntar rápido.
  final Set<int> topics;

  /// Cuántos temas unen comunidades distintas, aunque no estén en [bridges].
  final int candidates;

  /// Cuántas uniones se miraron para calcularlos: lo que dice que el costo
  /// crece con las uniones y no con su cuadrado. Es para las pruebas.
  final int visits;

  /// Si el tema de la posición [topic] es uno de los puentes.
  bool isBridge(int topic) => topics.contains(topic);
}
