import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/atlas/domain/services/atlas_builder.dart'
    show AtlasValueRow;
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_query_sql.dart';
import 'package:sinapsis/features/map/domain/entities/topic_graph.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';

class KnowledgeMapRepositoryImpl implements KnowledgeMapRepository {
  const KnowledgeMapRepositoryImpl({
    required AppDatabase database,
    required LibraryRepository library,
  }) : _db = database,
       _library = library;

  final AppDatabase _db;
  final LibraryRepository _library;

  @override
  Future<TopicGraphInput> readTopicInput(
    String definitionId, {
    LibraryQuery filter = const LibraryQuery(),
  }) async {
    final definitions = _db.propertyDefinitions;
    final definition = await (_db.select(
      definitions,
    )..where((d) => d.id.equals(definitionId))).getSingleOrNull();
    if (definition == null) return TopicGraphInput.empty(definitionId);

    final allowed = await _allowedItemIds(filter);
    final items = await _readItems(definitionId, allowed);
    return TopicGraphInput(
      definitionId: definitionId,
      definitionName: definition.name,
      values: await _readValues(definitionId),
      items: items,
      relations: await _readRelations({for (final item in items) item.id}),
    );
  }

  @override
  Stream<void> changes({LibraryQuery filter = const LibraryQuery()}) {
    final tables = {
      ...mapTables(_db),
      if (filter.isFiltered) ...mapFilterTables(_db),
    };
    return _db.tableUpdates(TableUpdateQuery.onAllTables(tables));
  }

  /// Los elementos que pasan el filtro, o `null` si no hay filtro y pasan
  /// todos —así no se pide la lista entera de identificadores para nada—.
  ///
  /// El filtro se resuelve en Dart sobre los elementos y no con un `IN (...)`
  /// en la consulta: una bóveda grande sin restricción puede pasar el límite
  /// de variables de SQLite.
  Future<Set<String>?> _allowedItemIds(LibraryQuery filter) async {
    if (!filter.isFiltered) return null;

    final result = await _library.matchingIds(
      filter.copyWith(limit: null, offset: 0),
    );
    return result.fold(
      (failure) => throw MapFilterFailed(failure),
      (ids) => ids.toSet(),
    );
  }

  Future<List<AtlasValueRow>> _readValues(String definitionId) async {
    final values = _db.propertyValues;
    final rows =
        await (_db.selectOnly(values)
              ..addColumns([values.id, values.value, values.parentId])
              ..where(values.definitionId.equals(definitionId)))
            .get();
    return [
      for (final row in rows)
        AtlasValueRow(
          id: row.read(values.id)!,
          label: row.read(values.value)!,
          parentId: row.read(values.parentId),
        ),
    ];
  }

  /// Los elementos vivos que pasan el filtro y tienen algún valor de la
  /// categoría.
  Future<List<TopicItem>> _readItems(
    String definitionId,
    Set<String>? allowed,
  ) async {
    final rows = await _db
        .customSelect(
          mapItemsSql,
          variables: [Variable.withString(definitionId)],
          readsFrom: mapTables(_db).toSet(),
        )
        .get();
    // Las columnas se toman de `data` y no con `read`: con miles de filas, la
    // conversión tipada de cada columna era una parte grande del tiempo.
    final items = <TopicItem>[];
    for (final row in rows) {
      final data = row.data;
      final valueIds = data['value_ids'] as String?;
      if (valueIds == null) continue;
      final id = data['id'] as String;
      if (allowed != null && !allowed.contains(id)) continue;
      items.add(
        TopicItem(id: id, valueIds: valueIds.split(mapValueIdSeparator)),
      );
    }
    return items;
  }

  /// Las relaciones entre dos elementos de [itemIds]: las que tienen un extremo
  /// en la papelera, o que el filtro dejó afuera, se descartan acá.
  Future<List<TopicRelation>> _readRelations(Set<String> itemIds) async {
    final rows = await _db
        .customSelect(mapRelationsSql, readsFrom: mapTables(_db).toSet())
        .get();
    final relations = <TopicRelation>[];
    for (final row in rows) {
      final data = row.data;
      final from = data['from_id'] as String;
      final to = data['to_id'] as String;
      if (!itemIds.contains(from) || !itemIds.contains(to)) continue;
      relations.add(
        TopicRelation(
          fromItemId: from,
          toItemId: to,
          kind: RelationKind.values.byName(data['kind'] as String),
          reviewed: data['reviewed'] == 1,
        ),
      );
    }
    return relations;
  }
}

/// La biblioteca no pudo resolver el filtro del mapa. Es un error del cálculo,
/// que el motor del mapa atrapa y muestra sin afectar a ninguna otra pantalla;
/// la biblioteca ya lo registró.
class MapFilterFailed implements Exception {
  const MapFilterFailed(this.failure);

  final Failure failure;

  @override
  String toString() =>
      'No se pudo resolver el filtro del mapa: ${failure.message}';
}
