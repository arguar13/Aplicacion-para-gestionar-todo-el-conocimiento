import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_atlas_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_atlas_repository.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

/// Lo que el Atlas de la IA lee y escribe (F27): el paso de la cola y, para
/// la interfaz, deshacer una ubicación en el árbol
/// (`AiAtlasRepository.undoTopicPlacement`).
final aiAtlasRepositoryProvider = Provider<AiAtlasRepository>((ref) {
  return AiAtlasRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    library: ref.watch(libraryRepositoryProvider),
    organize: ref.watch(organizeRepositoryProvider),
    runs: ref.watch(aiRunRepositoryProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});
