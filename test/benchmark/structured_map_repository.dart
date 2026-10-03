import 'dart:async';

import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/entities/schema.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/entities/topic_items.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';

/// El repositorio del mapa de la bóveda sintética, con los temas con la forma
/// de una bóveda de verdad (ver `structured_topics.dart`).
///
/// Lee de la base real todo lo que no es el grafo de temas —el tablero, el
/// esquema, los elementos de un tema— y entrega, en lugar de lo que la base
/// tiene asignado al azar, un [TopicGraphInput] ya armado: así el mapa se mide
/// con comunidades de verdad y con el mismo árbol de temas.
///
/// Además deja simular una escritura ([write]): cambia lo que se lee y avisa,
/// como avisaría la base, para medir el recálculo en caliente y que la
/// interfaz no se detenga mientras ocurre.
class StructuredMapRepository implements KnowledgeMapRepository {
  StructuredMapRepository(this._real, this._input);

  final KnowledgeMapRepository _real;
  TopicGraphInput _input;
  final _changes = StreamController<void>.broadcast();

  /// Lo que se lee ahora como grafo de temas.
  TopicGraphInput get input => _input;

  /// Cambia lo que se lee y avisa que algo se escribió.
  void write(TopicGraphInput replacement) {
    _input = replacement;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  @override
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) async => _input;

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) =>
      _changes.stream;

  @override
  Future<MapDashboard> readDashboard({
    LibraryQuery filter = const LibraryQuery(),
  }) => _real.readDashboard(filter: filter);

  @override
  Future<List<SchemaLink>> schemaLinks(
    SchemaRef node, {
    int limit = kSchemaFanOut,
  }) => _real.schemaLinks(node, limit: limit);

  @override
  Future<List<SchemaLink>> readMapNotes({int limit = kMaxMapNotes}) =>
      _real.readMapNotes(limit: limit);

  @override
  Future<TopicItemsGraph> readTopicItems(
    String valueId, {
    int limit = kMaxGraphItems,
  }) => _real.readTopicItems(valueId, limit: limit);

  @override
  Future<LinkGraph> readLinkGraph({
    LibraryQuery filter = const LibraryQuery(),
    String? focusId,
    int limit = kMaxGraphItems,
  }) => _real.readLinkGraph(filter: filter, focusId: focusId, limit: limit);
}
