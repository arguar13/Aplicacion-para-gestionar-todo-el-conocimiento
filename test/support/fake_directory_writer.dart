// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'dart:typed_data';

import 'package:sinapsis/features/export/domain/services/directory_writer.dart';

/// Guarda en memoria en vez de escribir en un disco de verdad.
class FakeDirectoryWriter implements DirectoryWriter {
  FakeDirectoryWriter({this.error});

  /// Si está, se lanza en vez de escribir — para probar una carpeta que se
  /// resiste. Mutable a propósito: se puede activar a mitad de una prueba.
  Object? error;

  /// Lo que se guardó, por nombre de archivo.
  final written = <String, Uint8List>{};

  String? lastDirectoryPath;

  @override
  Future<void> writeFile({
    required String directoryPath,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (error != null) throw error!;

    lastDirectoryPath = directoryPath;
    written[fileName] = bytes;
  }
}
