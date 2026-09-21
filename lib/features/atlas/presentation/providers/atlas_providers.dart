import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/atlas/data/repositories/atlas_repository_impl.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/domain/repositories/atlas_repository.dart';

/// Cascada de inyección del feature. La capa de presentación depende de este
/// repositorio; nunca de la base de datos directamente.
///
/// Vive tanto como la app —no es `autoDispose`— porque su caché es lo que hace
/// que volver al Atlas no recalcule: una caché que muere al cerrar la pantalla
/// no guarda nada.
final atlasRepositoryProvider = Provider<AtlasRepository>((ref) {
  final repository = AtlasRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// El Atlas de una categoría, que se actualiza solo.
///
/// `autoDispose`: el stream mantiene una suscripción a los cambios de la base,
/// y sin esto seguiría recomponiéndose con el Atlas cerrado.
final atlasProvider = StreamProvider.autoDispose.family<AtlasSnapshot, String>(
  (ref, definitionId) =>
      ref.watch(atlasRepositoryProvider).watchAtlas(definitionId),
);
