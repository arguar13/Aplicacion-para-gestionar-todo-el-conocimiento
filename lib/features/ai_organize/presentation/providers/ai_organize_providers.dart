import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/ai_organize/data/repositories/ai_run_repository_impl.dart';
import 'package:sinapsis/features/ai_organize/domain/repositories/ai_run_repository.dart';

/// Las pasadas de la IA y lo que «no era» (F27). La capa de presentación —y
/// la cola de la IA— dependen de este repositorio, nunca de la base.
final aiRunRepositoryProvider = Provider<AiRunRepository>((ref) {
  return AiRunRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  );
});
