import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
// Solo para el enlace [FileChooser] del comentario de la clase; el análisis
// estático no ve esa referencia dentro de un doc comment.
// ignore: unused_import
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';

/// Abre la cámara del dispositivo y trae la foto que se sacó.
///
/// Aparte de [FileChooser] y no un método más ahí, porque son dos acciones
/// distintas para quien captura: una trae un archivo que ya existe, la otra
/// crea uno nuevo en el momento. Compartir la interfaz las confundiría en el
/// selector de tipo, donde "Imagen" abre la galería y "Cámara" saca una
/// foto.
// ignore: one_member_abstracts
abstract interface class CameraChooser {
  /// Saca una foto y la devuelve, o `null` si se canceló sin sacar ninguna.
  Future<CapturedFile?> takePhoto();
}

/// El usuario no dio permiso para usar la cámara.
///
/// Se distingue de cancelar porque pide una acción distinta: cancelar es
/// "ahora no", y esto es "hay que ir a los ajustes del sistema".
class CameraAccessDeniedException implements Exception {
  const CameraAccessDeniedException();

  @override
  String toString() => 'Sin permiso para usar la cámara del dispositivo';
}
