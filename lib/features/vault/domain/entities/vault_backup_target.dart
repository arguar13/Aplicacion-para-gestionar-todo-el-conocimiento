import 'package:flutter/foundation.dart';

/// Dónde eligió el usuario guardar la copia de la bóveda.
///
/// Es opaco para quien lo recibe: lo arma el selector de archivos del sistema y
/// solo ese selector sabe escribirlo. En Android es una CARPETA —el URI de su
/// árbol de documentos, lo único con lo que el sistema deja escribir en una
/// carpeta ajena— y el archivo se crea adentro con [fileName]; en escritorio es
/// la ruta del archivo mismo, con su nombre.
@immutable
class VaultBackupTarget {
  const VaultBackupTarget({required this.location, required this.fileName});

  /// Una carpeta (URI de árbol de documentos) o la ruta del archivo, según la
  /// plataforma.
  final String location;

  /// El nombre del archivo de la copia.
  final String fileName;

  @override
  bool operator ==(Object other) =>
      other is VaultBackupTarget &&
      other.location == location &&
      other.fileName == fileName;

  @override
  int get hashCode => Object.hash(location, fileName);

  @override
  String toString() => 'VaultBackupTarget($location, $fileName)';
}
