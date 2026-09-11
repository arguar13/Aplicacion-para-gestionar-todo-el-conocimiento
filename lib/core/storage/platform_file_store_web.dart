import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/opfs_file_store.dart';

/// El almacén de archivos en la web: el sistema de archivos privado del
/// origen (OPFS). Ver la decisión 9 en docs/arquitectura.md.
FileStore createFileStore() {
  return const OpfsFileStore();
}
