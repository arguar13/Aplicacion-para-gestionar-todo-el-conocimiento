// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/photo_library_chooser.dart';

/// Una galería de fotos que devuelve lo que se le diga (F42), igual que
/// `FakeCameraChooser`.
class FakePhotoLibraryChooser implements PhotoLibraryChooser {
  FakePhotoLibraryChooser({this.photo, this.error});

  /// Lo que devuelve. `null` simula cerrar la galería sin elegir nada.
  final CapturedFile? photo;

  /// Si está, se lanza en vez de devolver.
  final Object? error;

  /// Cuántas veces se abrió.
  int timesOpened = 0;

  @override
  Future<CapturedFile?> pickPhoto() async {
    timesOpened++;
    if (error != null) throw error!;

    return photo;
  }
}
