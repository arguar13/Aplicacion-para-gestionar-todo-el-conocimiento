import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sinapsis/features/capture/data/services/captured_file_on_disk.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// El selector de archivos del sistema operativo.
class SystemFileChooser implements FileChooser {
  const SystemFileChooser();

  @override
  Future<CapturedFile?> pickOne() async {
    final result = await _pick(allowMultiple: false);
    final picked = result?.files.singleOrNull;
    if (picked == null) return null;
    return _fileFrom(picked);
  }

  @override
  Future<List<CapturedFile>> pickMany() async {
    final result = await _pick(allowMultiple: true);
    final picked = result?.files ?? const <PlatformFile>[];

    final files = <CapturedFile>[];
    for (final file in picked) {
      final captured = await _fileFrom(file);
      if (captured != null) files.add(captured);
    }
    return files;
  }

  Future<FilePickerResult?> _pick({required bool allowMultiple}) async {
    try {
      return await FilePicker.pickFiles(
        // Los bytes se piden solo en web, donde no hay rutas y son lo único
        // que llega. En el resto se lee del disco: dejar que el selector
        // cargue de una un archivo de cien megas, y quedarse encima con dos
        // copias en memoria, es justo lo que hace que una app muera sin
        // explicación en un teléfono modesto.
        withData: kIsWeb,
        allowMultiple: allowMultiple,
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
  }

  Future<CapturedFile?> _fileFrom(PlatformFile picked) async {
    // En la web no hay rutas: lo único que llega son los bytes.
    final bytes = picked.bytes;
    if (bytes != null) return CapturedFile(name: picked.name, bytes: bytes);

    final path = picked.path;
    if (path == null) return null;
    return capturedFileOnDisk(File(path), name: picked.name);
  }
}
