import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/open_app_file_opener.dart';
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

final fileOpenerProvider = Provider<FileOpener>((ref) {
  return const OpenAppFileOpener();
});
