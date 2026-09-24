// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// Un selector de archivos que devuelve lo que se le diga.
///
/// Abrir el selector de verdad necesita un sistema operativo con una ventana:
/// es lo único de todo el camino de captura que no se puede probar. Con este
/// doble, lo que sí se puede probar —que el archivo llegue entero, que
/// cancelar no rompa nada, que la falta de permiso se avise— se prueba.
class FakeFileChooser implements FileChooser {
  FakeFileChooser({this.file, this.files = const [], this.error});

  /// Lo que devuelve [pickOne]. `null` simula que el usuario canceló.
  final CapturedFile? file;

  /// Lo que devuelve [pickMany]. Vacía simula que el usuario canceló.
  final List<CapturedFile> files;

  /// Si está, se lanza en vez de devolver, en cualquiera de los dos.
  final Object? error;

  /// Cuántas veces se abrió, sumando [pickOne] y [pickMany].
  int timesOpened = 0;

  @override
  Future<CapturedFile?> pickOne() async {
    timesOpened++;
    if (error != null) throw error!;

    return file;
  }

  @override
  Future<List<CapturedFile>> pickMany() async {
    timesOpened++;
    if (error != null) throw error!;

    return files;
  }
}
