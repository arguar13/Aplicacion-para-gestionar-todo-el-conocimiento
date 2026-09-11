import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/local_file_store.dart';

/// El almacén de archivos originales.
///
/// Va en el directorio de documentos de la app y no en el de caché: el
/// sistema operativo borra la caché cuando necesita espacio, sin avisar, y
/// perder el PDF original rompería la promesa central de la app.
final fileStoreProvider = Provider<FileStore>((ref) {
  return const LocalFileStore(rootDirectory: getApplicationDocumentsDirectory);
});
