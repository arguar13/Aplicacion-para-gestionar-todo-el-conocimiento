import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Qué recorte del Explorador se está mirando: solo lo ya procesado
/// (`ProcessingState.ready` —esto es la vitrina de resultados, no la cola
/// de trabajo—), acotado por los filtros de tipo, etiqueta y propiedad que
/// el usuario vaya sumando.
///
/// Mismo patrón que `LibraryQueryNotifier`, pero sin búsqueda de texto ni
/// paginación: acá el punto es explorar filtrando, no buscar algo puntual
/// ni recorrer miles de elementos por tandas.
class ExplorerQueryNotifier extends StateNotifier<LibraryQuery> {
  ExplorerQueryNotifier()
    : super(const LibraryQuery(processingStates: {ProcessingState.ready}));

  /// Suma o quita un tipo de fuente del filtro.
  void toggleSourceKind(SourceKind kind) {
    final kinds = Set<SourceKind>.from(state.sourceKinds);
    if (!kinds.remove(kind)) kinds.add(kind);
    state = state.copyWith(sourceKinds: kinds);
  }

  /// Suma o quita una etiqueta del filtro.
  void toggleTagId(String tagId) {
    final tagIds = Set<String>.from(state.tagIds);
    if (!tagIds.remove(tagId)) tagIds.add(tagId);
    state = state.copyWith(tagIds: tagIds);
  }

  /// Suma o quita un valor de propiedad del filtro.
  void togglePropertyValueId(String valueId) {
    final ids = Set<String>.from(state.propertyValueIds);
    if (!ids.remove(valueId)) ids.add(valueId);
    state = state.copyWith(propertyValueIds: ids);
  }

  /// Deja SOLO el filtro por el valor [valueId] de una propiedad —una rama del
  /// Atlas—: lo que tiene ese valor o uno de sus subtemas. Lo demás se quita:
  /// se llega desde otra pantalla a mirar una cosa, no a sumarla a lo que
  /// hubiera.
  void focusOnValue(String valueId) {
    state = LibraryQuery(
      processingStates: state.processingStates,
      propertyValueIds: {valueId},
    );
  }

  void clearFilters() {
    state = state.copyWith(
      sourceKinds: const {},
      tagIds: const {},
      propertyValueIds: const {},
    );
  }

  bool get hasActiveFilters =>
      state.sourceKinds.isNotEmpty ||
      state.tagIds.isNotEmpty ||
      state.propertyValueIds.isNotEmpty;
}

final explorerQueryNotifierProvider =
    StateNotifierProvider.autoDispose<ExplorerQueryNotifier, LibraryQuery>(
      (ref) => ExplorerQueryNotifier(),
    );
