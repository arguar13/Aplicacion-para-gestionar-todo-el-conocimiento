import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';

/// Qué recorte de «Procesado» se está mirando (F41): búsqueda, filtros y orden
/// en un solo lugar, como `LibraryQueryNotifier` para la Biblioteca.
class ProcessedQueryNotifier extends StateNotifier<ProcessedQuery> {
  ProcessedQueryNotifier() : super(const ProcessedQuery(limit: pageSize));

  /// Cuántos documentos se piden por tanda: la misma cuenta que la Biblioteca
  /// —ver `LibraryQueryNotifier.pageSize`—. La fila no trae texto, así que lo
  /// que cuesta una tanda no depende de cuánto midan los documentos.
  static const pageSize = 100;

  /// Una búsqueda nueva vuelve a la primera tanda.
  void search(String text) {
    final trimmed = text.trim();
    state = state.copyWith(
      searchText: trimmed.isEmpty ? null : trimmed,
      limit: pageSize,
    );
  }

  /// Entra o sale de un tema, como en la Biblioteca: elegir el que ya está
  /// vuelve a «todos». `null` sale del que haya.
  void selectSpace(String? spaceId) {
    state = state.copyWith(
      spaceId: state.spaceId == spaceId ? null : spaceId,
      limit: pageSize,
    );
  }

  /// Suma o quita un tipo de fuente de origen.
  void toggleSourceKind(SourceKind kind) {
    final kinds = {...state.sourceKinds};
    if (!kinds.remove(kind)) kinds.add(kind);
    state = state.copyWith(sourceKinds: kinds, limit: pageSize);
  }

  /// Suma o quita una de las partes que tiene que tener.
  void toggleSection(ProcessedSection section) {
    final sections = {...state.sections};
    if (!sections.remove(section)) sections.add(section);
    state = state.copyWith(sections: sections, limit: pageSize);
  }

  /// Suma o quita «tiene la copia del original» (decisión H): vale, como las
  /// partes, cualquiera de las elegidas.
  void toggleOriginal() => state = state.copyWith(
    withOriginal: !state.withOriginal,
    limit: pageSize,
  );

  /// Ordena por [sort]. Por título va de la A a la Z; lo demás, lo más
  /// reciente arriba —ver `ProcessedQuery.descending`—.
  void sortBy(ProcessedSort sort) {
    state = state.copyWith(
      sortBy: sort,
      descending: sort != ProcessedSort.title,
      limit: pageSize,
    );
  }

  /// Quita los filtros y conserva la búsqueda y el orden, como en la
  /// Biblioteca: el botón sale cuando los filtros dejaron la lista vacía, y
  /// borrar de paso lo escrito sería hacer más de lo pedido.
  void clearFilters() {
    state = state.copyWith(
      spaceId: null,
      sourceKinds: const {},
      sections: const {},
      withOriginal: false,
      limit: pageSize,
    );
  }

  /// Trae la próxima tanda, pidiendo más de lo mismo.
  void loadMore() {
    state = state.copyWith(limit: (state.limit ?? pageSize) + pageSize);
  }

  /// Cuántos filtros hay puestos: el número del botón.
  int get activeFilterCount =>
      state.sourceKinds.length +
      state.sections.length +
      (state.withOriginal ? 1 : 0) +
      (state.spaceId == null ? 0 : 1);

  bool get hasActiveFilters => activeFilterCount > 0;

  /// Sale del tema elegido si ya no está entre [spaces]: se pudo borrar desde
  /// los filtros de otra pantalla, que siguen vivas al cambiar de pestaña.
  void releaseDeletedSpace(List<Space> spaces) {
    final spaceId = state.spaceId;
    if (spaceId != null && spaces.every((space) => space.id != spaceId)) {
      selectSpace(null);
    }
  }
}

final processedQueryNotifierProvider =
    StateNotifierProvider.autoDispose<ProcessedQueryNotifier, ProcessedQuery>((
      ref,
    ) {
      final notifier = ProcessedQueryNotifier();
      ref.listen(allSpacesProvider, (_, next) {
        final spaces = next.valueOrNull;
        if (spaces != null) notifier.releaseDeletedSpace(spaces);
      });
      return notifier;
    });
