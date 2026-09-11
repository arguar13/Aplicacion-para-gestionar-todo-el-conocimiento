import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/local_file_store.dart';

/// El almacén de archivos fuera de la web: `dart:io` sobre el directorio de
/// documentos de la app.
FileStore createFileStore() {
  return const LocalFileStore(rootDirectory: getApplicationDocumentsDirectory);
}
