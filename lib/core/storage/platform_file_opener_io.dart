import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/open_app_file_opener.dart';

/// El que abre archivos fuera de la web: le pide al sistema operativo que
/// lo abra con la app que tenga asociada.
FileOpener createFileOpener({required FileStore files}) {
  return const OpenAppFileOpener();
}
