import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:sinapsis/features/vault/domain/services/free_space_probe.dart';

/// El espacio libre según el sistema, con `disk_space_plus`.
///
/// El complemento solo existe en Android e iOS —las plataformas donde vive la
/// bóveda—: en escritorio no hay implementación y preguntarle lanza
/// `MissingPluginException`. Ahí, como cuando el directorio no existe o el
/// sistema no contesta, el dato «no se sabe» es `null`, no un error ni un
/// cero: quien pregunta decide qué hace sin él.
class DiskSpacePlusFreeSpaceProbe implements FreeSpaceProbe {
  const DiskSpacePlusFreeSpaceProbe();

  @override
  Future<int?> freeBytesAt(String path) async {
    try {
      final megabytes = await DiskSpacePlus().getFreeDiskSpaceForPath(path);
      if (megabytes == null || megabytes < 0) return null;
      // Redondear hacia abajo: decir que hay un poco menos de lo que hay
      // es el error seguro.
      return (megabytes * 1024 * 1024).floor();
    } on Exception {
      // `MissingPluginException`, `PlatformException` y el `Exception` que el
      // complemento lanza por sí mismo cuando el directorio no existe.
      return null;
    }
  }
}
