import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_target.dart';
import 'package:sinapsis/features/vault/domain/services/vault_backup_file_gateway.dart';

/// El nombre con el que se le muestra al usuario dónde quedó la copia en
/// Android, a partir del URI del árbol de documentos que eligió —
/// `content://com.android.externalstorage.documents/tree/primary%3ADownload`
/// es «primary:Download»— y el nombre del archivo.
///
/// Aparte de [SystemVaultBackupFileGateway] para poder probarla sin un
/// `MethodChannel` de por medio: es la única parte de esa clase que es lógica
/// propia en Android.
String describeSafTarget(String treeUri, String fileName) {
  final marker = treeUri.indexOf('/tree/');
  final encoded = marker < 0
      ? treeUri
      : treeUri.substring(marker + '/tree/'.length);
  // El árbol puede venir con un documento adentro: `<árbol>/document/<doc>`.
  final tree = encoded.split('/document/').first;
  var folder = tree;
  // Un `%` mal formado se muestra como vino: solo se decodifica lo que se
  // puede.
  if (RegExp(r'^(?:[^%]|%[0-9A-Fa-f]{2})*$').hasMatch(tree)) {
    try {
      folder = Uri.decodeComponent(tree);
    } on FormatException {
      // Bytes que no son UTF-8: también tal cual.
    }
  }
  return '$folder/$fileName';
}

/// [VaultBackupFileGateway] sobre `file_picker` y el Storage Access Framework
/// de Android, igual que `SystemFileSaver` y `SystemDirectoryChooser` del resto
/// de la app.
///
/// La copia se guarda desde un ARCHIVO, copiándolo por tandas, y nunca desde
/// bytes: `FilePicker.saveFile` en el teléfono exige los bytes en memoria, y
/// una copia de la bóveda puede pesar cientos de megas.
///  - En Android, el usuario elige una CARPETA (SAF) y el sistema copia el
///    archivo adentro con `pasteLocalFile`: es lo único con lo que Android
///    deja escribir en una carpeta ajena, incluidas las que reserva a una
///    colección de medios (ver `SafDirectoryWriter`).
///  - En escritorio, `file_picker` devuelve la ruta de un archivo de verdad y
///    se copia con `dart:io`.
class SystemVaultBackupFileGateway implements VaultBackupFileGateway {
  const SystemVaultBackupFileGateway();

  /// Solo Android tiene almacenamiento con ámbito.
  bool get _usesStorageAccessFramework => !kIsWeb && Platform.isAndroid;

  @override
  Future<VaultBackupTarget?> chooseTarget({required String fileName}) async {
    if (_usesStorageAccessFramework) {
      final folder = await SafUtil().pickDirectory(writePermission: true);
      final uri = folder?.uri;
      if (uri == null) return null;
      return VaultBackupTarget(location: uri, fileName: fileName);
    }

    // Sin `bytes`: en escritorio solo devuelve dónde guardar; el archivo lo
    // copia `save`.
    final path = await FilePicker.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (path == null) return null;
    return VaultBackupTarget(location: path, fileName: p.basename(path));
  }

  @override
  Future<String> save({
    required VaultBackupTarget target,
    required String sourcePath,
  }) async {
    if (_usesStorageAccessFramework) {
      await SafStream().pasteLocalFile(
        sourcePath,
        target.location,
        target.fileName,
        'application/zip',
        overwrite: true,
      );
      return describeSafTarget(target.location, target.fileName);
    }

    // El selector del sistema ya le preguntó al usuario si quería reemplazar
    // un archivo que existía.
    await File(sourcePath).copy(target.location);
    return target.location;
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
