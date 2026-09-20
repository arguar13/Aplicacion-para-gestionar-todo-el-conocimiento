import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/schema_too_old_exception.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview_outcome.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_rejection.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// Lee una copia ya elegida y dice qué traería a esta bóveda, sin escribir nada
/// (F11).
///
/// Es el paso que va entre elegir el archivo y fusionarlo: el usuario ve qué
/// va a pasar antes de decidir. Una copia que no sirve —de una versión más
/// nueva, demasiado vieja, o que no es una copia— vuelve como
/// [VaultMergePreviewRejected] y no como un fallo: es el archivo equivocado, no
/// una falla de la app.
class PreviewVaultMergeUseCase
    implements UseCase<VaultMergePreviewOutcome, Uint8List> {
  const PreviewVaultMergeUseCase({required VaultBackupService backupService})
    : _backupService = backupService;

  final VaultBackupService _backupService;

  @override
  Future<Either<Failure, VaultMergePreviewOutcome>> call(
    Uint8List params,
  ) async {
    try {
      final preview = await _backupService.previewMerge(params);
      return right(VaultMergePreviewOutcome.ready(preview: preview));
    } on VaultBackupTooNewException catch (e) {
      return right(
        VaultMergePreviewOutcome.rejected(
          rejection: VaultMergeRejection.tooNew(
            backupVersion: e.backupVersion,
            currentVersion: e.currentVersion,
          ),
        ),
      );
    } on SchemaTooOldException catch (e) {
      return right(
        VaultMergePreviewOutcome.rejected(
          rejection: VaultMergeRejection.tooOld(
            backupVersion: e.from,
            minimumVersion: e.minimum,
          ),
        ),
      );
    } on InvalidVaultBackupException {
      return right(
        const VaultMergePreviewOutcome.rejected(
          rejection: VaultMergeRejection.invalid(),
        ),
      );
      // Cualquier otra cosa —el disco, la base— no es culpa del archivo.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      return left(Failure.unexpected(message: '$e'));
    }
  }
}
