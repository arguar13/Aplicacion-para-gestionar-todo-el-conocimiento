import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/capture/domain/services/photo_library_chooser.dart';

/// La galería del sistema operativo, vía `image_picker` —el mismo paquete
/// que ya abre la cámara—: en Android, el selector de fotos del sistema; en
/// iOS, el de Fotos; en escritorio, el selector de archivos filtrado a
/// imágenes.
class SystemPhotoLibraryChooser implements PhotoLibraryChooser {
  const SystemPhotoLibraryChooser();

  @override
  Future<CapturedFile?> pickPhoto() async {
    final XFile? photo;
    try {
      // Sin achicarla: el modelo la mira entera y la miniatura se decodifica
      // a su tamaño al dibujarla (`thumbnailDecodeWidth`).
      photo = await ImagePicker().pickImage(source: ImageSource.gallery);
    } on PlatformException catch (e) {
      // El plugin informa la falta de permiso con este código en iOS; el
      // selector de fotos de Android no lo pide.
      if (e.code == 'photo_access_denied') {
        throw const FileAccessDeniedException();
      }
      rethrow;
    }
    if (photo == null) return null;

    return CapturedFile(name: photo.name, bytes: await photo.readAsBytes());
  }
}
