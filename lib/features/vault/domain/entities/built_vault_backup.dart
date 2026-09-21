import 'package:flutter/foundation.dart';

/// Una copia completa de la bóveda ya armada en un archivo temporal, a la
/// espera de que se guarde donde el usuario diga.
///
/// Es un archivo y no bytes porque puede pesar cientos de megas: nunca entera
/// en memoria. Quien la pidió es quien la suelta cuando termina, sea cual sea
/// el resultado: `VaultBackupService.discardBackup`.
@immutable
class BuiltVaultBackup {
  const BuiltVaultBackup({required this.path, required this.sizeBytes});

  /// La ruta del `.zip` armado.
  final String path;

  /// Lo que pesa, en bytes.
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is BuiltVaultBackup &&
      other.path == path &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(path, sizeBytes);

  @override
  String toString() => 'BuiltVaultBackup($path, $sizeBytes bytes)';
}
