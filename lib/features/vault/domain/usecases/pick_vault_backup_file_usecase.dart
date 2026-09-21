import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_file_pick.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Deja elegir un `.zip` de copia y confirma que tenga la forma esperada,
/// sin fusionar nada todavía —eso es `MergeVaultBackupUseCase`, un paso aparte
/// porque entre elegir el archivo y fusionarlo la presentación muestra qué
/// traería (`PreviewVaultMergeUseCase`) y pide confirmación, y ninguna de las
/// dos cosas es asunto de este caso de uso.
class PickVaultBackupFileUseCase
    implements UseCase<VaultBackupFilePick, NoParams> {
  const PickVaultBackupFileUseCase({
    required VaultBackupService backupService,
    required VaultBackupFileGateway gateway,
  }) : _backupService = backupService,
       _gateway = gateway;

  final VaultBackupService _backupService;
  final VaultBackupFileGateway _gateway;

  @override
  Future<Either<Failure, VaultBackupFilePick>> call(NoParams params) async {
    final path = await _gateway.pickZip();
    if (path == null) {
      return right(const VaultBackupFilePick.cancelled());
    }

    final isValid = await _backupService.isValidBackup(path);
    if (!isValid) {
      // Un archivo que no sirve no se va a usar: no hay por qué dejarlo.
      await _gateway.discardPicked();
      return right(const VaultBackupFilePick.invalid());
    }

    return right(VaultBackupFilePick.selected(path: path));
  }
}
