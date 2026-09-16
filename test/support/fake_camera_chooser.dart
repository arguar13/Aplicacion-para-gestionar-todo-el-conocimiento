// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';

/// Una cámara que devuelve lo que se le diga.
///
/// Abrirla de verdad necesita una cámara real detrás: es lo único de la
/// tarjeta "Cámara" que no se puede probar. Con este doble, lo que sí se
/// puede probar —que la foto llegue entera, que cancelar no rompa nada, que
/// la falta de permiso se avise— se prueba, igual que con `FakeFileChooser`.
class FakeCameraChooser implements CameraChooser {
  FakeCameraChooser({this.photo, this.error});

  /// Lo que devuelve. `null` simula que el usuario cerró la cámara sin
  /// sacar ninguna foto.
  final CapturedFile? photo;

  /// Si está, se lanza en vez de devolver.
  final Object? error;

  /// Cuántas veces se abrió.
  int timesOpened = 0;

  @override
  Future<CapturedFile?> takePhoto() async {
    timesOpened++;
    if (error != null) throw error!;

    return photo;
  }
}
