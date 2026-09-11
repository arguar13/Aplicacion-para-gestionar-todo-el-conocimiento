import 'dart:typed_data';

/// Entrega de una vez varios archivos armados en memoria, para cuando no
/// hay una carpeta real donde escribirlos uno por uno —la web—.
///
/// Aparte de `DirectoryWriter` a propósito: aquel escribe de a un archivo
/// por llamado porque el usuario ya eligió dónde, y eso no existe en un
/// navegador. Acá entran todos juntos porque recién ahí hay algo que
/// empaquetar y ofrecer.
// ignore: one_member_abstracts
abstract interface class PackageDownloader {
  /// Arma un `.zip` con [files] —nombre de archivo a bytes— y dispara su
  /// descarga con el nombre [zipFileName]. Devuelve ese mismo nombre.
  Future<String> downloadAsZip(
    Map<String, Uint8List> files, {
    required String zipFileName,
  });
}
