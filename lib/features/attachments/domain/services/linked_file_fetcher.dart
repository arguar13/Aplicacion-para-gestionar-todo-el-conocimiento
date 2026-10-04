/// Un archivo que se bajó y ya está guardado.
class FetchedFile {
  const FetchedFile({
    required this.relativePath,
    required this.bytes,
    required this.contentType,
    required this.fileName,
    required this.finalUrl,
  });

  /// Dónde quedó, relativo al almacén.
  final String relativePath;
  final int bytes;

  /// El tipo que dijo el servidor, en minúsculas y sin parámetros.
  final String? contentType;

  /// El nombre con que lo ofreció el servidor, o el de la dirección.
  final String fileName;

  /// De dónde vino, después de las redirecciones.
  final Uri finalUrl;
}

/// Baja un archivo que enlaza una página y lo guarda (F30): acotado, de a uno
/// por servidor, solo de internet y sin tenerlo entero en memoria.
///
/// Lanza lo que lanza `BoundedDownloader` —el tope, el espacio, un tipo que
/// no se quiere, un estado del servidor— y `PrivateNetworkException` si la
/// dirección es de la red local.
// ignore: one_member_abstracts
abstract interface class LinkedFileFetcher {
  /// Baja [url] a la carpeta de [storeId] —en [folder], si se da—, sin pasar
  /// de [maxBytes]. Con [unique], un nombre que ya está no se pisa.
  ///
  /// [preferredName] es el nombre que se le quiere dar (el de la página); si
  /// no tiene extensión, se le suma la del archivo que llegó.
  Future<FetchedFile> fetch(
    Uri url, {
    required String storeId,
    required int maxBytes,
    String? folder,
    bool unique = true,
    String? preferredName,
    bool Function(String? contentType)? accept,
    Future<void>? whenCancelled,
    void Function(int received, int? total)? onProgress,
  });
}
