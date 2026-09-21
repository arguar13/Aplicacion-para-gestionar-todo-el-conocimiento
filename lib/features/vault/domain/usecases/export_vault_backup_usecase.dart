import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/vault/domain/entities/built_vault_backup.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_export_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Arma la copia completa de la bóveda y la guarda donde el usuario diga.
///
/// Pide dónde guardarla ANTES de armarla —igual que
/// `ExportNotebookLmPackageUseCase`—: armar la copia de una bóveda grande lleva
/// minutos, y cancelar el selector no puede costar eso. La copia se arma en un
/// archivo temporal y se pasa al destino por tandas, sin que ni ella ni la
/// base pasen enteras por la memoria; el temporal se suelta al terminar, sea
/// cual sea el resultado.
class ExportVaultBackupUseCase
    implements UseCase<VaultBackupExportResult, NoParams> {
  const ExportVaultBackupUseCase({
    required VaultBackupService backupService,
    required VaultBackupFileGateway gateway,
    required Clock clock,
  }) : _backupService = backupService,
       _gateway = gateway,
       _clock = clock;

  final VaultBackupService _backupService;
  final VaultBackupFileGateway _gateway;
  final Clock _clock;

  @override
  Future<Either<Failure, VaultBackupExportResult>> call(NoParams params) async {
    BuiltVaultBackup? built;
    try {
      final target = await _gateway.chooseTarget(
        fileName: 'sinapsis-backup-${_timestamp()}.zip',
      );
      if (target == null) {
        return right(const VaultBackupExportResult.cancelled());
      }

      built = await _backupService.buildBackupFile();
      final saved = await _gateway.save(target: target, sourcePath: built.path);

      return right(
        VaultBackupExportResult.completed(
          path: saved,
          sizeBytes: built.sizeBytes,
        ),
      );
      // Puede fallar por espacio en disco, permisos de la carpeta elegida, o
      // un disco externo que se desconecta a mitad de la escritura —ninguno
      // con un tipo propio en dart:io—, igual que en la exportación de
      // NotebookLM.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    } finally {
      if (built != null) await _backupService.discardBackup(built);
    }
  }

  String _timestamp() {
    final now = _clock();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}-'
        '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }
}
