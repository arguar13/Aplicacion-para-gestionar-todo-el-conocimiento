import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// [FileSaver] sobre `file_picker`.
///
/// Se le pasan los bytes al propio selector en vez de escribirlos por
/// cuenta propia con `dart:io` después de recibir una ruta: es lo único que
/// funciona en la web, donde no hay sistema de archivos al que escribir, y
/// en el resto de las plataformas hace exactamente lo mismo que escribir a
/// mano — así que no hay razón para tener dos caminos.
class SystemFileSaver implements FileSaver {
  const SystemFileSaver();

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(fileName: fileName, bytes: bytes);
  }
}
