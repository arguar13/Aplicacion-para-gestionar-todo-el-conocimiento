// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'dart:typed_data';

import 'package:sinapsis/features/export/domain/services/file_saver.dart';

/// Guarda en memoria en vez de abrir un selector de verdad.
class FakeFileSaver implements FileSaver {
  FakeFileSaver({this.path = '/guardado', this.error});

  /// La ruta que "elige" el usuario. `null` simula cancelar el diálogo.
  final String? path;

  /// Si está, se lanza en vez de guardar. Mutable a propósito: se puede
  /// activar a mitad de una prueba, después de armar el resto del escenario.
  Object? error;

  /// Lo último que se le pidió guardar, para comprobarlo en las pruebas.
  String? savedFileName;
  Uint8List? savedBytes;

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (error != null) throw error!;

    savedFileName = fileName;
    savedBytes = bytes;
    return path;
  }
}
