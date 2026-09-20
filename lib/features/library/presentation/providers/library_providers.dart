import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/features/library/data/repositories/library_repository_impl.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/domain/entities/search_hit.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    files: ref.watch(fileStoreProvider),
    duplicateSuggestionGenerator: ref.watch(
      duplicateSuggestionGeneratorProvider,
    ),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});

/// La biblioteca que cumple una consulta, actualizándose sola.
///
/// Es `family` porque cada pantalla mira un recorte distinto —todo, lo
/// pendiente, lo etiquetado de tal manera— y cada uno merece su propio
/// stream en vez de que todos filtren sobre una lista común traída entera.
///
/// Es `autoDispose` porque el stream mantiene abierta una suscripción a los
/// cambios de la base: sin esto, cada consulta que alguna vez se haya mirado
/// seguiría recomponiéndose para siempre, aunque nadie la esté viendo.
final libraryItemsProvider = StreamProvider.autoDispose
    .family<List<KnowledgeItem>, LibraryQuery>((ref, query) {
      return ref.watch(libraryRepositoryProvider).watch(query);
    });

/// Los resultados de una búsqueda de texto, cada uno con DÓNDE está lo que se
/// encontró —el minuto, la página—, actualizándose solos.
///
/// Aparte de [libraryItemsProvider] porque trae más: la cita sale de la misma
/// pasada por el índice que elige los resultados. La pantalla usa este cuando
/// hay texto buscado, y aquel cuando no.
final librarySearchProvider = StreamProvider.autoDispose
    .family<List<SearchHit>, LibraryQuery>((ref, query) {
      return ref.watch(libraryRepositoryProvider).watchSearch(query);
    });

/// Un elemento concreto, actualizándose solo.
///
/// Emite `null` cuando el elemento deja de existir, y la pantalla de detalle
/// usa eso para cerrarse: seguir mostrando algo que se acaba de borrar es
/// peor que volver a la lista.
final libraryItemProvider = StreamProvider.autoDispose
    .family<KnowledgeItem?, String>((ref, id) {
      return ref.watch(libraryRepositoryProvider).watchById(id);
    });
