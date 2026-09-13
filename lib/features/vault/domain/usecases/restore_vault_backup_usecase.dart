import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_import_result.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Reemplaza la base y los archivos de esta bóveda con los de un `.zip` ya
/// elegido y validado por `PickVaultBackupFileUseCase`.
///
/// Se le pasan los bytes directamente y no una ruta: la presentación ya los
/// tiene en memoria desde que los validó, y volver a leerlos del disco sería
/// trabajo repetido sin ningún beneficio.
class RestoreVaultBackupUseCase
    implements UseCase<VaultBackupImportResult, Uint8List> {
  const RestoreVaultBackupUseCase({required VaultBackupService backupService})
    : _backupService = backupService;

  final VaultBackupService _backupService;

  @override
  Future<Either<Failure, VaultBackupImportResult>> call(
    Uint8List params,
  ) async {
    try {
      await _backupService.restoreBackup(params);
      return right(const VaultBackupImportResult.completed());
      // El archivo ya se validó antes de llegar acá: lo que puede fallar
      // ahora es escribir en el directorio de documentos de la propia
      // app —espacio en disco, permisos—, no que el archivo esté mal
      // formado.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: '$e'));
    }
  }
}
