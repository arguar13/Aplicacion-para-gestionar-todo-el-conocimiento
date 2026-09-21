import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/map/data/repositories/knowledge_map_repository_impl.dart';
import 'package:sinapsis/features/map/domain/entities/knowledge_map_state.dart';
import 'package:sinapsis/features/map/domain/repositories/knowledge_map_repository.dart';
import 'package:sinapsis/features/map/domain/services/knowledge_map_engine.dart';

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

/// El mapa de un pedido, que se actualiza solo.
///
/// `autoDispose`: el stream mantiene una suscripción a los cambios de la base,
/// y sin esto seguiría escuchándola con el mapa cerrado.
final knowledgeMapProvider = StreamProvider.autoDispose
    .family<KnowledgeMapState, MapRequest>(
      (ref, request) => ref.watch(knowledgeMapEngineProvider).watch(request),
    );
