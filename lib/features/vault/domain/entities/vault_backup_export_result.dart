import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_backup_export_result.freezed.dart';

/// Cómo terminó de armar la copia completa de la bóveda.
///
/// Cancelar el selector de guardado no es un fallo de dominio, igual que en
/// la exportación de un paquete para NotebookLM.
@freezed
sealed class VaultBackupExportResult with _$VaultBackupExportResult {
  const factory VaultBackupExportResult.cancelled() =
      VaultBackupExportCancelled;

  const factory VaultBackupExportResult.completed({
    required String path,
    required int sizeBytes,
  }) = VaultBackupExportCompleted;
}
