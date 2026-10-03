import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';
import 'package:sinapsis/features/timeline/domain/repositories/timeline_repository.dart';

final timelineRepositoryProvider = Provider<TimelineRepository>((ref) {
  return TimelineRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    library: ref.watch(libraryRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
});

/// Los filtros de la línea de tiempo: la misma consulta que entiende la
/// biblioteca, así "qué elementos entran" tiene una sola respuesta.
///
/// Es propia de esta pantalla y no la de la biblioteca: filtrar el eje no
/// tiene que cambiar lo que se ve en la lista, ni al revés.
class TimelineFilterNotifier extends StateNotifier<LibraryQuery> {
  TimelineFilterNotifier() : super(const LibraryQuery());

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

  /// Deja SOLO el filtro por el valor [valueId] de una propiedad —una rama
  /// del Atlas—: los hechos con ese valor o con uno de sus subtemas.
  void filterByValue(String valueId) {
    state = LibraryQuery(propertyValueIds: {valueId});
  }

  /// Deja SOLO el filtro por el tema [spaceId] —una rama del Atlas de los
  /// temas (F28)—: los hechos de lo que está en ese tema.
  void filterBySpace(String spaceId) {
    state = LibraryQuery(spaceId: spaceId);
  }

  /// Quita el filtro por una rama del Atlas —un valor de propiedad o un
  /// tema— y deja lo demás.
  void clearBranchFilter() {
    state = state.copyWith(propertyValueIds: const {}, spaceId: null);
  }

  void clear() => state = const LibraryQuery();
}

final timelineFilterProvider =
    StateNotifierProvider.autoDispose<TimelineFilterNotifier, LibraryQuery>(
      (ref) => TimelineFilterNotifier(),
    );

/// Los eventos que cumplen `filter`, actualizándose solos.
///
/// `family` por la consulta: cada combinación de filtros es su propio stream,
/// y volver a una anterior no arma nada de cero si sigue viva.
final timelineEventsProvider = StreamProvider.autoDispose
    .family<List<TimelineEvent>, LibraryQuery>((ref, filter) {
      return ref.watch(timelineRepositoryProvider).watchEvents(filter);
    });
