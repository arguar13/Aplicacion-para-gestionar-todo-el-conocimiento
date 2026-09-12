import 'dart:io';

import 'package:sinapsis/features/export/data/services/local_directory_writer.dart';
import 'package:sinapsis/features/export/data/services/saf_directory_chooser.dart';
import 'package:sinapsis/features/export/data/services/saf_directory_writer.dart';
import 'package:sinapsis/features/export/data/services/system_directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// Solo Android tiene almacenamiento con ámbito: ahí, la carpeta que el
/// usuario elige para el paquete de NotebookLM hay que escribirla por el
/// Storage Access Framework —ver [SafDirectoryWriter] para el porqué—. En
/// el resto de las plataformas de escritorio, `file_picker` ya devuelve una
/// ruta de archivo de verdad, y `dart:io` la escribe sin nada de por medio.
///
/// Este archivo, y no `export_providers.dart`, es el que decide esto: acá
/// `dart:io` es seguro de usar porque el import condicional de
/// `directory_services.dart` garantiza que esta versión nunca se compila
/// para la web, donde `Platform.isAndroid` no tiene nada real que
/// contestar.
DirectoryChooser createDefaultDirectoryChooser() {
  return Platform.isAndroid
      ? const SafDirectoryChooser()
      : const SystemDirectoryChooser();
}

DirectoryWriter createDefaultDirectoryWriter() {
  return Platform.isAndroid
      ? const SafDirectoryWriter()
      : const LocalDirectoryWriter();
}
