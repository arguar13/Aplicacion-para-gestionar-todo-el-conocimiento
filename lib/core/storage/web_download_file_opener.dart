import 'dart:js_interop';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:web/web.dart' as web;

/// `FileOpener` para la web: no existe "abrir con la app del sistema", así
/// que la única respuesta razonable es que el navegador lo descargue, con
/// su nombre real.
class WebDownloadFileOpener implements FileOpener {
  const WebDownloadFileOpener({required FileStore files}) : _files = files;

  final FileStore _files;

  /// [path] acá es la ruta relativa que guarda la base, no una absoluta:
  /// en OPFS no hay tal cosa (`OpfsFileStore.resolve()` lanza a propósito),
  /// así que esta clase lee los bytes ella misma en vez de esperar que se
  /// los resuelvan antes.
  @override
  Future<FileOpenResult> open(String path) async {
    final bytes = await _files.read(path);
    if (bytes == null) return FileOpenResult.fileNotFound;

    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    try {
      web.HTMLAnchorElement()
        ..href = url
        ..setAttribute('download', p.basename(path))
        ..click();
      return FileOpenResult.done;
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }
}
