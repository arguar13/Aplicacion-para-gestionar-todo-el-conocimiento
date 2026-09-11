import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/platform_file_opener.dart';
import 'package:sinapsis/core/storage/platform_file_store.dart';

/// El almacén de archivos originales.
///
/// Fuera de la web va en el directorio de documentos de la app y no en el
/// de caché: el sistema operativo borra la caché cuando necesita espacio,
/// sin avisar, y perder el PDF original rompería la promesa central de la
/// app. En la web va al Origin Private File System —ver la decisión 9 en
/// docs/arquitectura.md—, elegido en tiempo de compilación por
/// `createFileStore()`.
final fileStoreProvider = Provider<FileStore>((ref) => createFileStore());

/// Abre el archivo original. Fuera de la web, con la app que el sistema
/// tenga asociada; en la web, que no tiene ese concepto, disparando una
/// descarga (`createFileOpener()`, ver la decisión 11 en
/// docs/arquitectura.md).
final fileOpenerProvider = Provider<FileOpener>((ref) {
  return createFileOpener(files: ref.watch(fileStoreProvider));
});
