import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// El selector de archivos del sistema operativo.
class SystemFileChooser implements FileChooser {
  const SystemFileChooser();

  @override
  Future<CapturedFile?> pickOne() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        // Los bytes se piden solo en web, donde no hay rutas y son lo único
        // que llega. En el resto se lee del disco: dejar que el selector
        // cargue de una un archivo de cien megas, y quedarse encima con dos
        // copias en memoria, es justo lo que hace que una app muera sin
        // explicación en un teléfono modesto.
        withData: kIsWeb,
        // No se filtra por extensión, que además es lo que hace el selector
        // por defecto: reconocer de qué se trata cada archivo es trabajo del
        // detector de formato, que mira los bytes. Filtrar acá dejaría afuera
        // lo que llega sin nombre desde otras apps.
      );
    } on PlatformException catch (e) {
      // El selector informa la falta de permiso como una excepción de
      // plataforma con este código.
      if (e.code == 'read_external_storage_denied') {
        throw const FileAccessDeniedException();
      }
      rethrow;
    }

    final picked = result?.files.singleOrNull;
    if (picked == null) return null;

    // El selector ya informa el tamaño sin haber leído el contenido: se
    // rechaza acá, antes de `_readFrom`, para no cargar en memoria un
    // archivo de cientos de megas que se va a descartar de todos modos.
    if (picked.size > CapturedFile.maxBytes) {
      throw const FileTooLargeException();
    }

    final bytes = picked.bytes ?? await _readFrom(picked.path);
    if (bytes == null) return null;

    return CapturedFile(name: picked.name, bytes: bytes);
  }

  Future<Uint8List?> _readFrom(String? path) async {
    if (path == null) return null;

    final file = File(path);
    // La ruta que entrega el selector puede haber caducado entre que el
    // usuario eligió y el sistema liberó el archivo temporal.
    if (!file.existsSync()) return null;

    return file.readAsBytes();
  }
}
