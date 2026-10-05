/// Un archivo que salió de un `.zip` y ya está guardado.
class ExpandedFile {
  const ExpandedFile({
    required this.relativePath,
    required this.entryName,
    required this.bytes,
  });

  /// Dónde quedó, relativo al almacén.
  final String relativePath;

  /// Cómo se llamaba adentro del `.zip`, con sus carpetas: "fotos/roma.jpg".
  final String entryName;
  final int bytes;
}

/// Un `.zip` que no se descomprime: se lo guarda tal cual. [reason] dice por
/// qué, para el registro.
class UnsafeArchiveException implements Exception {
  const UnsafeArchiveException(this.reason);

  final String reason;

  @override
  String toString() => 'No se descomprime el .zip: $reason';
}

/// Descomprime los `.zip` que trae una página (F30) en el «Contenido» de su
/// elemento, sin confiar en lo que dicen adentro.
// ignore: one_member_abstracts
abstract interface class ArchiveExpander {
  /// Descomprime [zipPath] —ya guardado— en la carpeta [folder] de
  /// [storeId], sin pasar de [maxBytes] descomprimidos.
  ///
  /// Si el `.zip` es hostil o desmedido —ver la implementación— lanza
  /// [UnsafeArchiveException] y no deja nada de lo que alcanzó a sacar.
  Future<List<ExpandedFile>> expand(
    String zipPath, {
    required String storeId,
    required String folder,
    required int maxBytes,
  });
}
