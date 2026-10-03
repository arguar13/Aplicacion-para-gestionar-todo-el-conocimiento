import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/entities/link_graph.dart';
import 'package:sinapsis/features/map/domain/entities/map_dashboard.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';
import 'package:sinapsis/features/map/domain/usecases/export_map_usecase.dart';

/// Cascada de inyección del feature. La capa de presentación depende del
/// motor; nunca de la base de datos directamente.
final knowledgeMapRepositoryProvider = Provider<KnowledgeMapRepository>((ref) {
  return KnowledgeMapRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    library: ref.watch(libraryRepositoryProvider),
  );
});

/// El motor del mapa. Vive tanto como la app —no es `autoDispose`— porque su
/// caché y sus recuerdos de comunidades son lo que hace que volver al mapa no
/// recalcule ni recolore.
final knowledgeMapEngineProvider = Provider<KnowledgeMapEngine>((ref) {
  final engine = KnowledgeMapEngine(
    repository: ref.watch(knowledgeMapRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Guardar el mapa como imagen o como dibujo, donde el usuario elija.
final exportMapUseCaseProvider = Provider<ExportMapUseCase>((ref) {
  return ExportMapUseCase(saver: ref.watch(fileSaverProvider));
});

/// El tablero de un pedido: lo que se cuenta además del grafo de temas.
///
/// Se vuelve a leer cuando el mapa se recalcula y no por su cuenta: comparte la
/// espera por lotes del motor, así que una importación grande no lo lee mil
/// veces.
final mapDashboardProvider = FutureProvider.autoDispose
    .family<MapDashboard, MapRequest>((ref, request) {
      ref.watch(
        knowledgeMapProvider(request).select(
          (state) => switch (state) {
            AsyncData(value: MapReady(:final snapshot)) => snapshot.sequence,
            _ => -1,
          },
        ),
      );
      return ref
          .watch(knowledgeMapRepositoryProvider)
          .readDashboard(filter: request.filter);
    });

/// Un pedido de mirar un elemento en la vista «Vínculos» del Mapa (F28): lo
/// deja «Ver en el Mapa» y lo toma el Mapa —abierto o la próxima vez que se
/// arme—, que lo vuelve a `null` al atenderlo.
///
/// Un pedido y no un parámetro de la ruta: el Mapa es un destino del shell que
/// sigue vivo entre pestañas, y pedir dos veces el mismo elemento —después de
/// haber cambiado de vista en el medio— tiene que volver a enfocarlo; una ruta
/// igual a la anterior no avisaría nada.
final mapLinksFocusRequestProvider = StateProvider<String?>((ref) => null);

/// Qué se pide a la vista «Vínculos»: sobre qué elementos —el filtro del
/// mapa— y en cuál poner el foco, si en alguno.
typedef MapLinksRequest = ({LibraryQuery filter, String? focusId});

/// Los elementos vinculados y sus vínculos (F28), que se actualizan solos:
/// vincular dos cosas se ve en el acto, sin la espera por lotes del grafo de
/// temas —acá no hay comunidades que recalcular—.
///
/// `autoDispose`: mantiene una suscripción a los cambios de la base.
final mapLinksProvider = StreamProvider.autoDispose
    .family<LinkGraph, MapLinksRequest>((ref, request) {
      final repository = ref.watch(knowledgeMapRepositoryProvider);
      return watchReads(
        changes: () => repository.changes(filter: request.filter),
        read: () => repository.readLinkGraph(
          filter: request.filter,
          focusId: request.focusId,
        ),
        telemetry: ref.watch(telemetryServiceProvider),
        hint: 'mapLinksProvider',
      );
    });

/// El mapa de un pedido, que se actualiza solo.
///
/// `autoDispose`: el stream mantiene una suscripción a los cambios de la base,
/// y sin esto seguiría escuchándola con el mapa cerrado.
final knowledgeMapProvider = StreamProvider.autoDispose
    .family<KnowledgeMapState, MapRequest>(
      (ref, request) => ref.watch(knowledgeMapEngineProvider).watch(request),
    );
