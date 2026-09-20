import 'dart:typed_data';

import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';

/// Arma y restaura una copia completa de la bóveda: la base de datos entera
/// y todos los archivos originales que guarda, empaquetados en un `.zip`.
///
/// Existe para poder usar la misma bóveda en dos dispositivos —la compu y el
/// celular, por ejemplo— sin sincronización automática entre ellos (decisión
/// 1 en docs/arquitectura.md: sin servidor propio, y ninguna sincronización
/// en tiempo real es gratis en esfuerzo). El camino es manual a propósito:
/// exportar acá, pasar el archivo como sea —un cable, una nube que el
/// usuario ya use—, e importar allá.
abstract interface class VaultBackupService {
  /// Los bytes del `.zip` con la base y los archivos originales. No toca
  /// nada del disco: quien llama decide dónde guardarlo.
  Future<Uint8List> buildBackup();

  /// Si [zipBytes] tiene la forma de una copia de Sinapsis —trae la base de
  /// datos adentro—, sin llegar a restaurar nada todavía. Se usa antes de
  /// pedirle confirmación al usuario: no tiene sentido advertirle que va a
  /// reemplazar toda su bóveda por un archivo que ni siquiera es una copia
  /// válida.
  Future<bool> isValidBackup(Uint8List zipBytes);

  /// Qué pasaría si se fusionara la copia [zipBytes] con esta bóveda, sin
  /// escribir nada (F11): cuántos elementos y cuántas otras cosas trae que
  /// esta bóveda no tiene, y cuántos archivos.
  ///
  /// Lanza [InvalidVaultBackupException] si no tiene la forma de una copia;
  /// [VaultBackupTooNewException] si es de una versión de Sinapsis más nueva
  /// que esta; y `SchemaTooOldException` si es de una tan vieja que esta no
  /// sabe actualizarla. La copia se abre aparte, en un temporal: si hay que
  /// actualizar su esquema se actualiza ELLA, nunca esta bóveda.
  Future<VaultMergePreview> previewMerge(Uint8List zipBytes);

  /// Reemplaza la base y los archivos originales de esta bóveda con los que
  /// traiga [zipBytes]. Lanza [InvalidVaultBackupException] si no tiene la
  /// forma esperada —no debería pasar si ya se llamó a [isValidBackup]
  /// antes, pero esto no confía en que quien llama lo haya hecho—.
  ///
  /// Después de esto, la conexión a la base que la app tenía abierta queda
  /// apuntando a un archivo que ya no existe: quien llama es responsable de
  /// cerrarla antes de invocar esto, y de que la app se reinicie después.
  Future<void> restoreBackup(Uint8List zipBytes);
}

/// La copia es de una versión de Sinapsis más nueva que esta: su base tiene un
/// esquema que esta versión no conoce (F11).
///
/// Leerla con lo que esta versión sabe podría perder o malentender datos, así
/// que se rechaza sin tocar nada; la respuesta es actualizar la app.
class VaultBackupTooNewException implements Exception {
  const VaultBackupTooNewException({
    required this.backupVersion,
    required this.currentVersion,
  });

  /// La versión de esquema de la base de la copia.
  final int backupVersion;

  /// La que esta versión de la app entiende.
  final int currentVersion;

  String get message =>
      'La copia es de una versión más nueva de Sinapsis (esquema '
      'v$backupVersion) y esta solo entiende hasta el v$currentVersion. '
      'Actualizá la app y volvé a intentarlo. No se modificó nada.';

  @override
  String toString() => 'VaultBackupTooNewException: $message';
}

/// El archivo elegido para restaurar no es una copia de Sinapsis —le falta
/// la base de datos adentro—.
class InvalidVaultBackupException implements Exception {
  const InvalidVaultBackupException(this.message);

  final String message;

  @override
  String toString() => 'Copia de bóveda inválida: $message';
}
