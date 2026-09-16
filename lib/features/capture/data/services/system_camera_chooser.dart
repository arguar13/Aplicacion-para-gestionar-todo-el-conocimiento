import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/domain/services/camera_chooser.dart';

/// La cámara del sistema operativo, vía `image_picker`.
class SystemCameraChooser implements CameraChooser {
  const SystemCameraChooser();

  @override
  Future<CapturedFile?> takePhoto() async {
    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(source: ImageSource.camera);
    } on PlatformException catch (e) {
      // El plugin informa la falta de permiso como una excepción de
      // plataforma con este código, igual en Android y en iOS.
      if (e.code == 'camera_access_denied') {
        throw const CameraAccessDeniedException();
      }
      rethrow;
    }
    if (photo == null) return null;

    return CapturedFile(name: photo.name, bytes: await photo.readAsBytes());
  }
}
