import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_backup_file_pick.freezed.dart';

/// El resultado de elegir un archivo para fusionar, ya validado.
///
/// [VaultBackupFileInvalid] existe aparte de un fallo de dominio porque no
/// es un error de la app: es que el usuario eligió el archivo equivocado, y
/// la respuesta es dejarlo elegir otro, no una pantalla de error.
@freezed
sealed class VaultBackupFilePick with _$VaultBackupFilePick {
  const factory VaultBackupFilePick.cancelled() = VaultBackupFileCancelled;

  const factory VaultBackupFilePick.invalid() = VaultBackupFileInvalid;

  /// [path] es la ruta del archivo elegido, ya comprobado.
  const factory VaultBackupFilePick.selected({required String path}) =
      VaultBackupFileSelected;
}
