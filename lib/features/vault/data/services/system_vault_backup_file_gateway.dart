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
  Future<Uint8List?> pickZip() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      // Los bytes se piden solo en web, donde no hay ruta al disco: en el
      // resto se lee del path, igual que `SystemFileChooser` — una copia de
      // la bóveda entera puede pesar cientos de megas, y `file_picker` la
      // cargaría dos veces en memoria si además se pidiera acá.
      withData: kIsWeb,
    );

    final picked = result?.files.singleOrNull;
    if (picked == null) return null;
    if (picked.bytes != null) return picked.bytes;

    final path = picked.path;
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    return file.readAsBytes();
  }
}
