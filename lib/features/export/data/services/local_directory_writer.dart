import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// [DirectoryWriter] sobre `dart:io`, directo: la carpeta ya la eligió el
/// usuario, así que no hay ninguna ruta que resolver ni ningún nombre que
/// sanear —a diferencia del almacén interno, acá el nombre es justamente lo
/// que el usuario va a ver al abrir la carpeta, y forzarlo a pasar por el
/// mismo saneo le cambiaría acentos y espacios sin necesidad—.
class LocalDirectoryWriter implements DirectoryWriter {
  const LocalDirectoryWriter();

  @override
  Future<void> writeFile({
    required String directoryPath,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final file = File(p.join(directoryPath, fileName));
    await file.writeAsBytes(bytes, flush: true);
  }
}
