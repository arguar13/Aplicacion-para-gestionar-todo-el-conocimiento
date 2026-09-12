import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// El tipo MIME de un nombre de archivo, a partir de su extensión.
///
/// Aparte de [SafDirectoryWriter] para poder probarla sin un `MethodChannel`
/// de por medio: es la única parte de esa clase que es lógica propia, el
/// resto es un llamado directo al plugin.
///
/// Solo cubre lo que este paquete llega a escribir en una carpeta ajena
/// —Markdown, texto plano y PDF, ver `ExporterRegistry`—; cualquier otra
/// extensión cae en `application/octet-stream`, el tipo genérico para
/// "bytes sin forma conocida", que Android acepta para cualquier archivo.
String mimeTypeForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();

  return switch (extension) {
    'md' => 'text/markdown',
    'txt' => 'text/plain',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

/// [DirectoryWriter] sobre el Storage Access Framework de Android.
///
/// `directoryPath` acá es, en realidad, el URI de árbol SAF que devolvió
/// `SafDirectoryChooser` —los dos se usan siempre juntos—, y escribir pasa
/// por `ContentResolver`/`DocumentFile`, no por `dart:io`. Es lo que hace
/// que esto funcione en cualquier carpeta que el usuario elija, incluidas
/// las que Android reserva a una colección de medios (Alarms, Ringtones,
/// Notifications, Podcasts, Music): ahí, escribir con `dart:io` sobre una
/// ruta adivinada fallaba con "Couldn't save to the chosen folder" —el
/// permiso del árbol SAF no es lo mismo que permiso de escritura directa
/// por el sistema de archivos, y el almacenamiento con ámbito de Android
/// solo concede lo segundo a través del propio SAF—.
class SafDirectoryWriter implements DirectoryWriter {
  const SafDirectoryWriter();

  @override
  Future<void> writeFile({
    required String directoryPath,
    required String fileName,
    required Uint8List bytes,
  }) async {
    await SafStream().writeFileBytes(
      directoryPath,
      fileName,
      mimeTypeForFileName(fileName),
      bytes,
      overwrite: true,
    );
  }
}
