import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/features/vault/data/services/local_vault_backup_service.dart';
import 'package:sinapsis/features/vault/data/services/system_vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';
import 'package:sinapsis/features/vault/domain/usecases/export_vault_backup_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/pick_vault_backup_file_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/restore_vault_backup_usecase.dart';

/// `autoDispose`: a diferencia de la sesión de la bóveda, esto no necesita
/// sobrevivir entre pantallas — se arma de nuevo cada vez que se entra a la
/// pantalla de copia de seguridad, sobre la conexión de base vigente en ese
/// momento.
final vaultBackupServiceProvider = Provider.autoDispose<VaultBackupService>((
  ref,
) {
  return LocalVaultBackupService(database: ref.watch(appDatabaseProvider));
});

final vaultBackupFileGatewayProvider =
    Provider.autoDispose<VaultBackupFileGateway>((ref) {
      return const SystemVaultBackupFileGateway();
    });

final exportVaultBackupUseCaseProvider =
    Provider.autoDispose<ExportVaultBackupUseCase>((ref) {
      return ExportVaultBackupUseCase(
        backupService: ref.watch(vaultBackupServiceProvider),
        gateway: ref.watch(vaultBackupFileGatewayProvider),
        clock: DateTime.now,
      );
    });

final pickVaultBackupFileUseCaseProvider =
    Provider.autoDispose<PickVaultBackupFileUseCase>((ref) {
      return PickVaultBackupFileUseCase(
        backupService: ref.watch(vaultBackupServiceProvider),
        gateway: ref.watch(vaultBackupFileGatewayProvider),
      );
    });

final restoreVaultBackupUseCaseProvider =
    Provider.autoDispose<RestoreVaultBackupUseCase>((ref) {
      return RestoreVaultBackupUseCase(
        backupService: ref.watch(vaultBackupServiceProvider),
      );
    });
