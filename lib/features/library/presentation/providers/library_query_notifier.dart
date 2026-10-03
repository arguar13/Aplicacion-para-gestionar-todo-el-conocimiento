import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

/// Qué recorte de la biblioteca se está mirando.
///
/// Guarda la consulta activa —búsqueda, filtros y orden— en un solo lugar,
/// para que la barra de búsqueda, los filtros y la lista no tengan que
/// mantener cada uno su pedacito y sincronizarlo con los demás.
class LibraryQueryNotifier extends StateNotifier<LibraryQuery> {
  LibraryQueryNotifier() : super(const LibraryQuery(limit: pageSize));

  /// Cuántos elementos se piden por tanda.
  ///
  /// Sin un límite, una biblioteca de miles de elementos se trae entera cada
  /// vez que algo cambia en la base —guardar una etiqueta, procesar un
  /// elemento de la cola— aunque la pantalla solo pueda mostrar unos pocos a
  /// la vez. Ver el comentario de `limit` en `LibraryQuery`.
  static const pageSize = 100;

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
      // Una consulta nueva vuelve a arrancar desde la primera tanda: seguir
      // pidiendo las mil filas que se habían acumulado paginando la consulta
      // anterior no tiene sentido para una búsqueda distinta.
      limit: pageSize,
    );
  }

  /// Suma o quita un tipo de fuente del filtro.
  void toggleSourceKind(SourceKind kind) {
    final kinds = Set<SourceKind>.from(state.sourceKinds);
    if (!kinds.remove(kind)) kinds.add(kind);
    state = state.copyWith(sourceKinds: kinds, limit: pageSize);
  }

  /// Suma o quita una etiqueta del filtro.
  void toggleTagId(String tagId) {
    final tagIds = Set<String>.from(state.tagIds);
    if (!tagIds.remove(tagId)) tagIds.add(tagId);
    state = state.copyWith(tagIds: tagIds, limit: pageSize);
  }

  /// Entra o sale de un espacio, como una carpeta: elegir el que ya está
  /// activo vuelve a "todos", a diferencia de las etiquetas —que se
  /// combinan— acá solo tiene sentido mirar un espacio a la vez. `null`
  /// sale del que haya.
  void selectSpace(String? spaceId) {
    state = state.copyWith(
      spaceId: state.spaceId == spaceId ? null : spaceId,
      limit: pageSize,
    );
  }

  void sortBy(LibrarySort sort, {bool descending = true}) {
    state = state.copyWith(
      sortBy: sort,
      descending: descending,
      limit: pageSize,
    );
  }

  /// Quita los filtros pero conserva la búsqueda.
  ///
  /// Son cosas distintas para quien las usa: el botón aparece cuando los
  /// filtros dejaron la lista vacía, y borrar de paso lo que escribió sería
  /// hacer más de lo que pidió.
  ///
  /// El tema también se suelta: vive en el mismo panel que el tipo y las
  /// etiquetas, y un "Limpiar filtros" que dejara puesto uno de los que se
  /// ven ahí no estaría limpiando lo que promete.
  void clearFilters() {
    state = state.copyWith(
      sourceKinds: const {},
      tagIds: const {},
      processingStates: const {},
      spaceId: null,
      limit: pageSize,
    );
  }

  /// Trae la próxima tanda.
  ///
  /// Sumar al límite en vez de guardar una lista aparte: el repositorio ya
  /// sabe traer "las primeras N que cumplen la consulta", así que pedir más
  /// es simplemente pedir un N más grande — no hace falta un mecanismo de
  /// paginación distinto del que ya existe.
  void loadMore() {
    state = state.copyWith(limit: (state.limit ?? pageSize) + pageSize);
  }

  bool get hasActiveFilters =>
      state.sourceKinds.isNotEmpty ||
      state.tagIds.isNotEmpty ||
      state.processingStates.isNotEmpty ||
      state.spaceId != null;

  /// Reemplaza el filtro y el orden enteros por los de una vista guardada
  /// (F16): misma consulta que se guardó, con `limit`/`offset` propios de
  /// esta sesión y no de la vista.
  void apply(LibraryQuery query) {
    state = query.copyWith(limit: pageSize, offset: 0);
  }

  /// Sale del tema elegido si ya no está entre [spaces]: se borró, desde el
  /// panel de filtros de esta pantalla o desde el del Explorador.
  void releaseDeletedSpace(List<Space> spaces) {
    final spaceId = state.spaceId;
    if (spaceId != null && spaces.every((space) => space.id != spaceId)) {
      selectSpace(null);
    }
  }
}

final libraryQueryNotifierProvider =
    StateNotifierProvider.autoDispose<LibraryQueryNotifier, LibraryQuery>((
      ref,
    ) {
      final notifier = LibraryQueryNotifier();
      // Un tema se puede borrar desde los filtros de la Biblioteca y desde
      // los del Explorador, y las dos pantallas siguen vivas al cambiar de
      // pestaña: la que no lo borró seguiría filtrando por un tema que ya no
      // existe, con la lista vacía sin decir por qué.
      ref.listen(allSpacesProvider, (_, next) {
        final spaces = next.valueOrNull;
        if (spaces != null) notifier.releaseDeletedSpace(spaces);
      });
      return notifier;
    });
