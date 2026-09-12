import 'package:sinapsis/features/export/data/services/local_directory_writer.dart';
import 'package:sinapsis/features/export/data/services/system_directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// En la web, `createExportNotebookLmPackageUseCase()`
/// (`export_notebooklm_usecase_factory_web.dart`) ni siquiera usa lo que
/// devuelven estas dos funciones —no hay carpeta que elegir, el paquete
/// sale como un `.zip`—, así que alcanza con cualquier implementación que
/// compile: no hace falta el Storage Access Framework, que además no
/// existe en un navegador.
DirectoryChooser createDefaultDirectoryChooser() {
  return const SystemDirectoryChooser();
}

DirectoryWriter createDefaultDirectoryWriter() {
  return const LocalDirectoryWriter();
}
