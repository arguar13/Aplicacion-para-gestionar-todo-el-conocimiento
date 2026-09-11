import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/web_download_file_opener.dart';

/// El que abre archivos en la web: no hay con qué "abrir con", así que
/// dispara una descarga.
FileOpener createFileOpener({required FileStore files}) {
  return WebDownloadFileOpener(files: files);
}
