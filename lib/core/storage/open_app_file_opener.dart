import 'package:open_app_file/open_app_file.dart' as plugin;
import 'package:sinapsis/core/storage/file_opener.dart';

/// Abre archivos con [`open_app_file`](https://pub.dev/packages/open_app_file),
/// BSD-3-Clause. Es el único candidato con soporte parejo en los seis
/// destinos del proyecto — Android, iOS, Windows, macOS, Linux y web—: los
/// demás, o solo cubren móvil, o dependen de complementos que esta app no
/// necesita para nada más.
class OpenAppFileOpener implements FileOpener {
  const OpenAppFileOpener();

  @override
  Future<FileOpenResult> open(String absolutePath) async {
    final result = await plugin.OpenAppFile.open(absolutePath);

    return switch (result.type) {
      plugin.ResultType.done => FileOpenResult.done,
      plugin.ResultType.fileNotFound => FileOpenResult.fileNotFound,
      plugin.ResultType.noAppToOpen => FileOpenResult.noAppAvailable,
      plugin.ResultType.permissionDenied ||
      plugin.ResultType.error => FileOpenResult.failed,
    };
  }
}
