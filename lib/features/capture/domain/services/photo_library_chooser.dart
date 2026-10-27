import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';

/// Trae una foto de la galería del teléfono (F42): la tarjeta «Fotos» de la
/// hoja «Agregar al chat».
///
/// Aparte de `FileChooser`, que abre el selector de archivos sin filtrar: en
/// Android esto abre el selector de fotos del sistema —las fotos en grilla,
/// por fecha, sin pedir permiso de lectura—, que es lo que se espera al tocar
/// «Fotos», no una lista de carpetas. Igual que la cámara, se prueba con un
/// doble.
// ignore: one_member_abstracts
abstract interface class PhotoLibraryChooser {
  /// Abre la galería y devuelve la foto elegida, o `null` si se cerró sin
  /// elegir ninguna. Si no hay permiso para ver las fotos, lanza
  /// `FileAccessDeniedException`: es el mismo "hay que ir a los ajustes" que
  /// con los archivos.
  Future<CapturedFile?> pickPhoto();
}
