import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_export_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Arma la copia completa de la bóveda y la guarda donde el usuario diga.
///
/// Arma los bytes primero y pide dónde guardarlos después —al revés que
/// `ExportNotebookLmPackageUseCase`, que pide la carpeta antes de armar
/// nada— porque acá no tiene sentido lo contrario: el `.zip` no cambia según
/// dónde se guarde, así que no hay ningún trabajo que evitar cancelando el
/// selector antes.
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
    try {
      final bytes = await _backupService.buildBackup();
      final path = await _gateway.saveZip(
        fileName: 'sinapsis-backup-${_timestamp()}.zip',
        bytes: bytes,
      );
      if (path == null) {
        return right(const VaultBackupExportResult.cancelled());
      }

      return right(
        VaultBackupExportResult.completed(path: path, sizeBytes: bytes.length),
      );
      // Puede fallar por espacio en disco, permisos de la carpeta elegida, o
      // un disco externo que se desconecta a mitad de la escritura —ninguno
      // con un tipo propio en dart:io—, igual que en la exportación de
      // NotebookLM.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.exportFailed(message: '$e'));
    }
  }

  String _timestamp() {
    final now = _clock();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}-'
        '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }
}
