import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Los filtros del mapa (F14, D8): la misma consulta que entiende la
/// biblioteca, así «qué elementos entran» tiene una sola respuesta y el mapa no
/// lleva un motor de filtros propio.
///
/// Son propios de esta pantalla y no los de la biblioteca: filtrar el mapa no
/// tiene que cambiar lo que se ve en la lista, ni al revés. Las tres vistas
/// —tablero, esquema y grafo— comparten estos.
class MapFilterNotifier extends StateNotifier<LibraryQuery> {
  MapFilterNotifier() : super(const LibraryQuery());

  void search(String text) {
    final trimmed = text.trim();
    state = state.copyWith(searchText: trimmed.isEmpty ? null : trimmed);
  }

  void toggleSourceKind(SourceKind kind) {
    final kinds = Set<SourceKind>.from(state.sourceKinds);
    if (!kinds.remove(kind)) kinds.add(kind);
    state = state.copyWith(sourceKinds: kinds);
  }

  void toggleTagId(String tagId) {
    final tagIds = Set<String>.from(state.tagIds);
    if (!tagIds.remove(tagId)) tagIds.add(tagId);
    state = state.copyWith(tagIds: tagIds);
  }

  /// Entra o sale de un tema de la biblioteca, como una carpeta: un elemento
  /// está en uno solo, así que se mira uno a la vez y elegir el que ya está
  /// puesto vuelve a "todos". Es lo mismo que hace la biblioteca.
  void toggleSpace(String spaceId) {
    state = state.copyWith(spaceId: state.spaceId == spaceId ? null : spaceId);
  }

  void clear() => state = const LibraryQuery();
}

/// Cuántos filtros tiene puestos una consulta: lo que el panel de filtros
/// muestra en su marca.
int activeMapFilters(LibraryQuery query) =>
    query.sourceKinds.length +
    query.tagIds.length +
    (query.spaceId == null ? 0 : 1) +
    (query.hasSearchText ? 1 : 0);

final mapFilterProvider =
    StateNotifierProvider.autoDispose<MapFilterNotifier, LibraryQuery>(
      (ref) => MapFilterNotifier(),
    );
