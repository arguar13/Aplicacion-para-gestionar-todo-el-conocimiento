import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Fusiona una copia ya elegida —por su ruta— con esta bóveda (F11).
///
/// Reemplaza a restaurar: no borra nada de lo que hay, no cierra la base ni
/// pide reiniciar la app. Es todo o nada —si una compuerta de seguridad no se
/// cumple, o algo falla, no se cambia nada— y por eso los tres finales
/// esperables son valores: se fusionó ([VaultMergeMerged]), la copia no sirve
/// ([VaultMergeRejected]) o se revirtió por una compuerta
/// ([VaultMergeReverted]). Solo lo inesperado —el disco, la base— es un fallo.
class MergeVaultBackupUseCase implements UseCase<VaultMergeOutcome, String> {
  const MergeVaultBackupUseCase({required VaultBackupService backupService})
    : _backupService = backupService;

  final VaultBackupService _backupService;

  @override
  Future<Either<Failure, VaultMergeOutcome>> call(String params) async {
    try {
      final result = await _backupService.mergeBackup(params);
      return right(VaultMergeOutcome.merged(result: result));
    } on VaultMergeGateException catch (e) {
      return right(VaultMergeOutcome.reverted(gate: e.gate));
    } on VaultBackupTooNewException catch (e) {
      return right(
        VaultMergeOutcome.rejected(
          rejection: VaultMergeRejection.tooNew(
            backupVersion: e.backupVersion,
            currentVersion: e.currentVersion,
          ),
        ),
      );
    } on SchemaTooOldException catch (e) {
      return right(
        VaultMergeOutcome.rejected(
          rejection: VaultMergeRejection.tooOld(
            backupVersion: e.from,
            minimumVersion: e.minimum,
          ),
        ),
      );
    } on InvalidVaultBackupException {
      return right(
        const VaultMergeOutcome.rejected(
          rejection: VaultMergeRejection.invalid(),
        ),
      );
      // Lo demás no es culpa del archivo: el disco, la base. La fusión se
      // revirtió igual —es una transacción—.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: '$e'));
    }
  }
}
