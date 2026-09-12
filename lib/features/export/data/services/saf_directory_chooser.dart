import 'package:saf_util/saf_util.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';

/// [DirectoryChooser] sobre el Storage Access Framework de Android.
///
/// A diferencia de `SystemDirectoryChooser` (que usa `file_picker` y termina
/// devolviendo una ruta de archivo adivinada a partir del URI elegido), este
/// devuelve el URI real de la carpeta —`content://...`—, sin traducirlo a
/// nada. Es justamente esa traducción la que hace que escribir después falle
/// en carpetas que Android reserva a una colección de medios (ver
/// `SafDirectoryWriter`): un `String?` sigue siendo la forma en que
/// [DirectoryChooser] se comunica con quien lo usa, pero acá adentro es un
/// URI, no una ruta.
class SafDirectoryChooser implements DirectoryChooser {
  const SafDirectoryChooser();

  @override
  Future<String?> pickDirectory() async {
    final picked = await SafUtil().pickDirectory(writePermission: true);
    return picked?.uri;
  }
}
