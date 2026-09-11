import 'package:sinapsis/core/storage/file_opener.dart';

/// Abridor de archivos de mentira, para comprobar qué se le pidió abrir sin
/// depender de que la máquina que corre las pruebas tenga una aplicación de
/// verdad instalada para cada tipo de archivo.
class FakeFileOpener implements FileOpener {
  FakeFileOpener({this.result = FileOpenResult.done});

  /// Lo que devuelve la próxima vez que se le pida abrir algo.
  FileOpenResult result;

  /// Las rutas que se le pidió abrir, en orden.
  final requested = <String>[];

  @override
  Future<FileOpenResult> open(String absolutePath) async {
    requested.add(absolutePath);
    return result;
  }
}
