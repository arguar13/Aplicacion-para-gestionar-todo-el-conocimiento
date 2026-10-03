import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

/// Qué recorte del Explorador se está mirando: solo lo ya procesado
/// (`ProcessingState.ready` —esto es la vitrina de resultados, no la cola
/// de trabajo—), acotado por los filtros de tema, tipo, etiqueta y propiedad
/// que el usuario vaya sumando.
///
/// Mismo patrón que `LibraryQueryNotifier`, pero sin búsqueda de texto ni
/// paginación: acá el punto es explorar filtrando, no buscar algo puntual
/// ni recorrer miles de elementos por tandas.
class ExplorerQueryNotifier extends StateNotifier<LibraryQuery> {
  ExplorerQueryNotifier()
    : super(const LibraryQuery(processingStates: {ProcessingState.ready}));

  /// Entra o sale de un tema, igual que en la Biblioteca —ver
  /// `LibraryQueryNotifier.selectSpace`—: uno a la vez, elegir el que ya
  /// está activo lo suelta, y `null` sale del que haya.
  void selectSpace(String? spaceId) {
    state = state.copyWith(spaceId: state.spaceId == spaceId ? null : spaceId);
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

  /// Suelta todos los filtros, también el tema: vive en el mismo panel, y un
  /// "Limpiar filtros" que dejara puesto uno de los que se ven ahí no estaría
  /// limpiando lo que promete. Lo procesado sigue siendo lo único que se ve:
  /// eso no es un filtro, es lo que el Explorador muestra.
  void clearFilters() {
    state = state.copyWith(
      sourceKinds: const {},
      tagIds: const {},
      propertyValueIds: const {},
      spaceId: null,
    );
  }

  bool get hasActiveFilters =>
      state.sourceKinds.isNotEmpty ||
      state.tagIds.isNotEmpty ||
      state.propertyValueIds.isNotEmpty ||
      state.spaceId != null;

  /// Sale del tema elegido si ya no está entre [spaces]: se borró, desde el
  /// panel de filtros de esta pantalla o desde el de la Biblioteca.
  void releaseDeletedSpace(List<Space> spaces) {
    final spaceId = state.spaceId;
    if (spaceId != null && spaces.every((space) => space.id != spaceId)) {
      selectSpace(null);
    }
  }
}

final explorerQueryNotifierProvider =
    StateNotifierProvider.autoDispose<ExplorerQueryNotifier, LibraryQuery>((
      ref,
    ) {
      final notifier = ExplorerQueryNotifier();
      // Por qué: ver la misma escucha en `libraryQueryNotifierProvider`.
      ref.listen(allSpacesProvider, (_, next) {
        final spaces = next.valueOrNull;
        if (spaces != null) notifier.releaseDeletedSpace(spaces);
      });
      return notifier;
    });
