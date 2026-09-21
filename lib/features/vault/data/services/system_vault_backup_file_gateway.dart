import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';

/// [VaultBackupFileGateway] sobre `file_picker`, igual que `SystemFileSaver`
/// y `SystemFileChooser` del resto de la app.
class SystemVaultBackupFileGateway implements VaultBackupFileGateway {
  const SystemVaultBackupFileGateway();

  @override
  Future<String?> saveZip({
    required String fileName,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(fileName: fileName, bytes: bytes);
  }

  @override
  Future<String?> pickZip() async {
    // Sin `withData`: nunca los bytes. Una copia de la bóveda entera puede
    // pesar cientos de megas y quien la lee lo hace del disco, por la ruta. Lo
    // que el selector devuelve es una ruta: la del archivo mismo en escritorio,
    // y en el teléfono la de una copia que arma en el almacenamiento temporal
    // de la app —copiada de a tandas, sin pasar entera por la memoria—.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    final path = result?.files.singleOrNull?.path;
    if (path == null) return null;
    if (!File(path).existsSync()) return null;

    return path;
  }

  @override
  Future<void> discardPicked() async {
    // Solo en el teléfono el selector deja una copia: en escritorio la ruta es
    // la del archivo del usuario, y borrarla sería borrarle su copia de
    // seguridad.
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await FilePicker.clearTemporaryFiles();
      // Es limpieza: que no se pueda no es motivo para fallar lo que ya
      // terminó bien.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}
