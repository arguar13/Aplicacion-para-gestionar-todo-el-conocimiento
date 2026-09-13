import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_backup_import_result.freezed.dart';

/// Cómo terminó de restaurar una copia completa de la bóveda.
///
/// [VaultBackupImportCompleted] no es "ya está": restaurar reemplaza la base
/// que la app tiene abierta, así que hace falta cerrar y volver a abrir para
/// que el cambio se vea en cada pantalla que ya tenía datos cargados.
@freezed
sealed class VaultBackupImportResult with _$VaultBackupImportResult {
  const factory VaultBackupImportResult.cancelled() =
      VaultBackupImportCancelled;

  const factory VaultBackupImportResult.completed() =
      VaultBackupImportCompleted;
}
