import 'dart:typed_data';

import 'package:sinapsis/features/vault/domain/entities/vault_merge_preview.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_merge_result.dart';

/// Arma y fusiona una copia completa de la bóveda: la base de datos entera
/// y todos los archivos originales que guarda, empaquetados en un `.zip`.
///
/// Existe para poder usar la misma bóveda en dos dispositivos —la compu y el
/// celular, por ejemplo— sin sincronización automática entre ellos (decisión
/// 1 en docs/arquitectura.md: sin servidor propio, y ninguna sincronización
/// en tiempo real es gratis en esfuerzo). El camino es manual a propósito:
/// exportar acá, pasar el archivo como sea —un cable, una nube que el
/// usuario ya use—, y fusionarlo allá con lo que ya hay.
abstract interface class VaultBackupService {
  /// Los bytes del `.zip` con la base y los archivos originales. No toca
  /// nada del disco: quien llama decide dónde guardarlo.
  Future<Uint8List> buildBackup();

  /// Si el archivo [zipPath] tiene la forma de una copia de Sinapsis —es un
  /// `.zip` y trae la base de datos adentro—, sin llegar a fusionar nada
  /// todavía. Se usa antes de pedirle confirmación al usuario: no tiene sentido
  /// mostrarle qué traería un archivo que ni siquiera es una copia válida.
  ///
  /// Las copias se leen del disco, por su ruta, y no se cargan en memoria: una
  /// copia de una bóveda grande puede pesar cientos de megas.
  Future<bool> isValidBackup(String zipPath);

  /// Qué pasaría si se fusionara la copia [zipPath] con esta bóveda, sin
  /// escribir nada (F11): cuántos elementos y cuántas otras cosas trae que
  /// esta bóveda no tiene, y cuántos archivos.
  ///
  /// Lanza [InvalidVaultBackupException] si no tiene la forma de una copia;
  /// [VaultBackupTooNewException] si es de una versión de Sinapsis más nueva
  /// que esta; y `SchemaTooOldException` si es de una tan vieja que esta no
  /// sabe actualizarla. La copia se abre aparte, en un temporal: si hay que
  /// actualizar su esquema se actualiza ELLA, nunca esta bóveda.
  Future<VaultMergePreview> previewMerge(String zipPath);

  /// Fusiona la copia [zipPath] con esta bóveda, sin borrar nada de lo que hay
  /// (F11): lo que la copia trae y acá no está se suma, y lo que las dos tienen
  /// se une campo a campo, quedándose con la versión que sigue a la otra; lo
  /// que no se puede decidir queda guardado como conflicto para que el usuario
  /// lo revise. El texto de una fuente no se pisa nunca.
  ///
  /// Es todo o nada: si una compuerta no se cumple o algo falla, ni la base ni
  /// los archivos quedan cambiados. Lanza lo mismo que [previewMerge] por una
  /// copia que no sirve, y `VaultMergeGateException` si la fusión se revirtió
  /// por una compuerta.
  ///
  /// No reemplaza nada ni pide reiniciar la app: la conexión abierta sigue
  /// siendo la misma.
  Future<VaultMergeResult> mergeBackup(String zipPath);
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

/// Una compuerta de la fusión no se cumplió: la fusión se revirtió entera
/// (F11).
class VaultMergeGateException implements Exception {
  const VaultMergeGateException(this.gate, this.message);

  /// Cuál: `items`, `counts`, `text` o `references`.
  final String gate;

  /// Qué se encontró, sin el contenido de ninguna fila.
  final String message;

  @override
  String toString() => 'VaultMergeGateException($gate): $message';
}
