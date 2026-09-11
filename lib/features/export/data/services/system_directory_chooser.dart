import 'package:file_picker/file_picker.dart';
import 'package:sinapsis/features/export/domain/services/directory_chooser.dart';

/// El selector de carpetas del sistema operativo.
class SystemDirectoryChooser implements DirectoryChooser {
  const SystemDirectoryChooser();

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();
}
