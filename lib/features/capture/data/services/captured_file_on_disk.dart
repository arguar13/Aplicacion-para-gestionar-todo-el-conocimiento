import 'dart:io';
import 'dart:typed_data';

import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

/// [file] como un [CapturedFile] en disco: su tamaño, sus primeros bytes y
/// cómo leerlo por partes —nunca entero en memoria (F21)—. `null` si la ruta
/// ya caducó: el sistema puede liberar el archivo temporal entre que el
/// usuario lo eligió o lo compartió y que la app lo toma.
Future<CapturedFile?> capturedFileOnDisk(File file, {String? name}) async {
  if (!file.existsSync()) return null;

  final size = await file.length();
  final handle = await file.open();
  final Uint8List head;
  try {
    head = await handle.read(CapturedFile.headBytes);
  } finally {
    await handle.close();
  }

  return CapturedFile.onDisk(
    name: name ?? file.uri.pathSegments.last,
    sizeInBytes: size,
    head: head,
    openRead: file.openRead,
  );
}
