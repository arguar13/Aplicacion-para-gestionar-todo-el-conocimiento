import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';

/// Qué recorte de la biblioteca se está mirando.
///
/// Guarda la consulta activa —búsqueda, filtros y orden— en un solo lugar,
/// para que la barra de búsqueda, los filtros y la lista no tengan que
/// mantener cada uno su pedacito y sincronizarlo con los demás.
class LibraryQueryNotifier extends StateNotifier<LibraryQuery> {
  LibraryQueryNotifier() : super(const LibraryQuery());

  void search(String text) {
    final trimmed = text.trim();

    state = state.copyWith(
      searchText: trimmed.isEmpty ? null : trimmed,
      // El orden cambia solo al empezar a buscar, y vuelve al salir.
      //
      // Quien escribe "paradigma" quiere lo que más habla de paradigma, no lo
      // último que guardó; y cuando borra la búsqueda, ordenar por relevancia
      // deja de significar nada. Hacerlo automático evita que el usuario
      // tenga que aprender que existe un orden por relevancia y acordarse de
      // elegirlo cada vez.
      sortBy: trimmed.isEmpty ? LibrarySort.capturedAt : LibrarySort.relevance,
    );
  }

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

  void sortBy(LibrarySort sort, {bool descending = true}) {
    state = state.copyWith(sortBy: sort, descending: descending);
  }

  /// Quita los filtros pero conserva la búsqueda.
  ///
  /// Son cosas distintas para quien las usa: el botón aparece cuando los
  /// filtros dejaron la lista vacía, y borrar de paso lo que escribió sería
  /// hacer más de lo que pidió.
  void clearFilters() {
    state = state.copyWith(
      sourceKinds: const {},
      tagIds: const {},
      processingStates: const {},
    );
  }

  bool get hasActiveFilters =>
      state.sourceKinds.isNotEmpty ||
      state.tagIds.isNotEmpty ||
      state.processingStates.isNotEmpty;
}

final libraryQueryNotifierProvider =
    StateNotifierProvider.autoDispose<LibraryQueryNotifier, LibraryQuery>(
      (ref) => LibraryQueryNotifier(),
    );
