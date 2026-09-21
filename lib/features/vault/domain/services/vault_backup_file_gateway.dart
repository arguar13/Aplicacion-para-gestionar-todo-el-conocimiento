import 'dart:typed_data';

import 'package:sinapsis/features/vault/domain/services/vault_backup_service.dart';

/// El selector del sistema operativo para guardar y elegir el archivo de
/// copia de la bóveda —aparte de [VaultBackupService], que no sabe nada de
/// diálogos, para poder probar cada uno por separado—.
abstract interface class VaultBackupFileGateway {
  /// Deja elegir dónde guardar [bytes]. La ruta elegida, o `null` si se
  /// cancela el selector.
  Future<String?> saveZip({required String fileName, required Uint8List bytes});

  /// Deja elegir un archivo `.zip` para fusionar. Su ruta en el disco, o `null`
  /// si se cancela el selector.
  ///
  /// La ruta y no los bytes: una copia de la bóveda entera puede pesar cientos
  /// de megas, y quien la lee lo hace del disco, a medida que la necesita. En
  /// el teléfono, esa ruta es una copia que el selector armó en el
  /// almacenamiento temporal de la app: [discardPicked] la borra.
  Future<String?> pickZip();

  /// Suelta lo que el selector dejó en el almacenamiento temporal de la app al
  /// elegir un archivo —en el teléfono, una copia entera de él—. Se llama al
  /// terminar con el archivo elegido, sirva o no.
  ///
  /// En escritorio no hay nada que soltar: la ruta que devolvió [pickZip] es la
  /// del archivo REAL del usuario, y no se toca.
  Future<void> discardPicked();
}
