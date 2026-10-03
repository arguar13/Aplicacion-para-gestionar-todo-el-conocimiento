import 'package:meta/meta.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/community_detection.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';

/// Qué mapa se pide (F14): los temas de una categoría, sobre los elementos que
/// pasan un filtro de la biblioteca.
///
/// Tiene igualdad por valor: dos pedidos iguales comparten el mismo cálculo.
@immutable
class MapRequest {
  const MapRequest(this.definitionId, {this.filter = const LibraryQuery()});

  final String definitionId;

  /// El filtro de la biblioteca —el mismo motor que en todas las pantallas—;
  /// sin restricciones, el mapa abarca todos los elementos vivos.
  final LibraryQuery filter;

  @override
  bool operator ==(Object other) =>
      other is MapRequest &&
      other.definitionId == definitionId &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(definitionId, filter);
}

/// Cuánto tardó cada parte de un cálculo del mapa.
class MapTimings {
  const MapTimings({
    required this.read,
    required this.build,
    required this.communities,
    required this.total,
  });

  /// Leer lo que hace falta de la base.
  final Duration read;

  /// Armar el grafo de temas, en el isolate.
  final Duration build;

  /// Agrupar los temas en comunidades, en el isolate.
  final Duration communities;

  /// De punta a punta, con el paso de los datos de un isolate al otro: es lo
  /// que espera quien mira el mapa.
  final Duration total;
}

/// Un mapa calculado: el grafo de temas y sus comunidades.
class KnowledgeMapSnapshot {
  const KnowledgeMapSnapshot({
    required this.request,
    required this.graph,
    required this.detection,
    required this.timings,
    required this.sequence,
    this.unassignedItemIds = const [],
  });

  final MapRequest request;
  final TopicGraph graph;
  final CommunityDetection detection;
  final MapTimings timings;

  /// Los elementos que pasan el filtro sin ningún valor de lo que se mira:
  /// lo que el grafo no puede ubicar y el Mapa ofrece organizar (F28).
  final List<String> unassignedItemIds;

  /// Cuántos cálculos había hecho el motor al terminar este: dos resultados
  /// iguales de cálculos distintos se distinguen por él.
  final int sequence;
}

/// Lo que el motor le cuenta a quien mira el mapa.
sealed class KnowledgeMapState {
  const KnowledgeMapState();
}

/// Todavía no hay ningún cálculo.
final class MapLoading extends KnowledgeMapState {
  const MapLoading();
}

/// El mapa, al día con lo último que se leyó de la base.
final class MapReady extends KnowledgeMapState {
  const MapReady(this.snapshot);

  final KnowledgeMapSnapshot snapshot;
}

/// El cálculo falló. Con [lastGood], quien mira puede seguir mostrando el mapa
/// anterior con un aviso; sin él, solo el error.
final class MapFailed extends KnowledgeMapState {
  const MapFailed(this.error, {this.lastGood});

  final Object error;
  final KnowledgeMapSnapshot? lastGood;
}
