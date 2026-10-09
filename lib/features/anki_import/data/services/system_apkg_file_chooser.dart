import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/anki_import/domain/services/apkg_file_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// El selector de archivos del sistema, para un `.apkg`.
class SystemApkgFileChooser implements ApkgFileChooser {
  const SystemApkgFileChooser();

  @override
  Future<String?> pick() async {
    try {
      // Sin filtrar por extensión: el sistema no conoce `.apkg` y en varios
      // dejaría el archivo apagado. Que sea un paquete de Anki lo comprueba
      // el lector, que mira el contenido y dice qué pasó.
      final result = await FilePicker.pickFiles();
      return result?.files.singleOrNull?.path;
    } on PlatformException catch (e) {
      if (e.code == 'read_external_storage_denied') {
        throw const FileAccessDeniedException();
      }
      rethrow;
    }
  }

  @override
  Future<void> release() async {
    try {
      await FilePicker.clearTemporaryFiles();
      // Solo Android e iOS dejan copias; en el resto no hay nada que limpiar y
      // el canal puede no existir.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Limpiar el temporal es una cortesía: si no se puede, el sistema lo
      // hace solo más tarde, y nada de lo importado depende de eso.
    }
  }
}
