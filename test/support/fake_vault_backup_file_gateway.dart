import 'dart:typed_data';

import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';

/// El selector de archivos de la copia, sin selector: devuelve la ruta que la
/// prueba le diga y anota cuántas veces le pidieron soltar lo que dejó.
class FakeVaultBackupFileGateway implements VaultBackupFileGateway {
  String? picked = '/copias/a.zip';

  /// Cuántas veces se soltó lo que el selector dejó.
  int discards = 0;

  @override
  Future<String?> pickZip() async => picked;

  @override
  Future<void> discardPicked() async => discards++;

  @override
  Future<String?> saveZip({
    required String fileName,
    required Uint8List bytes,
  }) async => null;
}
