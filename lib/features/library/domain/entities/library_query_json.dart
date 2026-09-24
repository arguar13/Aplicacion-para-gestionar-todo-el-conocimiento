import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// [query] como JSON, para guardarlo con nombre (F16): una vista guardada.
///
/// Solo lo que tiene sentido reusar entre sesiones —el filtro y el orden—.
/// [LibraryQuery.ids] queda afuera a propósito: es para quien ya sabe qué
/// elementos le interesan —los vecinos de un elemento en el grafo local—, no
/// algo que alguien nombre y guarde; y `limit`/`offset` son de la página que
/// se está mirando, no del filtro en sí.
Map<String, Object?> libraryQueryToJson(LibraryQuery query) => {
  if (query.searchText != null) 'searchText': query.searchText,
  'sourceKinds': [for (final kind in query.sourceKinds) kind.name],
  'tagIds': query.tagIds.toList(),
  'propertyValueIds': query.propertyValueIds.toList(),
  if (query.spaceId != null) 'spaceId': query.spaceId,
  'processingStates': [for (final state in query.processingStates) state.name],
  'sortBy': query.sortBy.name,
  'descending': query.descending,
};

/// El inverso de [libraryQueryToJson]. Un valor que no se reconoce —de una
/// versión más vieja de la app, o un dato corrupto— se ignora en vez de
/// fallar: una vista guardada rota se aplica vacía, no rompe la pantalla.
LibraryQuery libraryQueryFromJson(Map<String, Object?> json) => LibraryQuery(
  searchText: json['searchText'] as String?,
  sourceKinds: {
    for (final name in (json['sourceKinds'] as List?)?.cast<String>() ?? [])
      if (SourceKind.values.where((k) => k.name == name).firstOrNull
          case final kind?)
        kind,
  },
  tagIds: (json['tagIds'] as List?)?.cast<String>().toSet() ?? {},
  propertyValueIds:
      (json['propertyValueIds'] as List?)?.cast<String>().toSet() ?? {},
  spaceId: json['spaceId'] as String?,
  processingStates: {
    for (final name
        in (json['processingStates'] as List?)?.cast<String>() ?? [])
      if (ProcessingState.values.where((s) => s.name == name).firstOrNull
          case final state?)
        state,
  },
  sortBy:
      LibrarySort.values.where((s) => s.name == json['sortBy']).firstOrNull ??
      LibrarySort.capturedAt,
  descending: json['descending'] as bool? ?? true,
);
