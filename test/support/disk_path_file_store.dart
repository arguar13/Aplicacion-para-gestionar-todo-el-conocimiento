import 'in_memory_file_store.dart';

/// Un almacén en memoria cuyos archivos tienen una ruta en el disco, como en
/// el teléfono: lo que necesita lo que se hace sonar desde un archivo (F47,
/// paso 5).
class DiskPathFileStore extends InMemoryFileStore {
  @override
  Future<String?> localPathOf(String relativePath) async =>
      await exists(relativePath) ? '/disco/$relativePath' : null;
}
