import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';

/// Devuelve la carpeta que se le diga, sin abrir un selector de verdad.
class FakeDirectoryChooser implements DirectoryChooser {
  FakeDirectoryChooser({this.path = '/carpeta-elegida'});

  /// La carpeta que "elige" el usuario. `null` simula cancelar. Mutable a
  /// propósito: una prueba puede cancelar una vez y elegir de verdad la
  /// siguiente, sin armar dos selectores distintos.
  String? path;

  int callCount = 0;

  @override
  Future<String?> pickDirectory() async {
    callCount++;
    return path;
  }
}
