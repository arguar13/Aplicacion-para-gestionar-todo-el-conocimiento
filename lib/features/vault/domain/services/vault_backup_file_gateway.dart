import 'dart:typed_data';

import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// El selector del sistema operativo para guardar y elegir el archivo de
/// copia de la bóveda —aparte de [VaultBackupService], que no sabe nada de
/// diálogos, para poder probar cada uno por separado—.
abstract interface class VaultBackupFileGateway {
  /// Deja elegir dónde guardar [bytes]. La ruta elegida, o `null` si se
  /// cancela el selector.
  Future<String?> saveZip({required String fileName, required Uint8List bytes});

  /// Deja elegir un archivo `.zip` para fusionar. Sus bytes, o `null` si se
  /// cancela el selector.
  Future<Uint8List?> pickZip();
}
