import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/features/vault/data/services/disk_space_plus_free_space_probe.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_compaction_advisor.dart';
import 'package:sinapsis/features/vault/data/services/sqlite_vault_compactor.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/services/compaction_advisor.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_notifier.dart';
import 'package:sinapsis/features/vault/presentation/providers/compaction_state.dart';

final freeSpaceProbeProvider = Provider<FreeSpaceProbe>(
  (ref) => const DiskSpacePlusFreeSpaceProbe(),
);

/// `autoDispose`, como el resto de lo de la copia de seguridad: se arma sobre
/// la conexión de base vigente cada vez que se entra a la pantalla.
final compactionAdvisorProvider = Provider.autoDispose<CompactionAdvisor>((
  ref,
) {
  return SqliteCompactionAdvisor(
    database: ref.watch(appDatabaseProvider),
    freeSpace: ref.watch(freeSpaceProbeProvider),
  );
});

final vaultCompactorProvider = Provider.autoDispose<VaultCompactor>((ref) {
  return SqliteVaultCompactor(
    database: ref.watch(appDatabaseProvider),
    advisor: ref.watch(compactionAdvisorProvider),
  );
});

/// Qué hay para recuperar ahora. Barata: se vuelve a medir cada vez que se lee
/// después de invalidarla, y la ficha de Ajustes y la pantalla la comparten.
final compactionAssessmentProvider =
    FutureProvider.autoDispose<CompactionAssessment>((ref) {
      return ref.watch(compactionAdvisorProvider).assess();
    });

final compactionNotifierProvider =
    StateNotifierProvider.autoDispose<CompactionNotifier, CompactionState>((
      ref,
    ) {
      return CompactionNotifier(
        compactor: ref.watch(vaultCompactorProvider),
        logger: ref.watch(appLoggerProvider),
      );
    });
