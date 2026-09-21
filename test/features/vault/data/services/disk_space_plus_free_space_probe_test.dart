import 'package:disk_space_plus/disk_space_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/data/services/disk_space_plus_free_space_probe.dart';

/// El complemento por dentro: lo que devuelve, en megabytes, o lo que lanza.
class _FakePlatform extends DiskSpacePlusPlatform {
  _FakePlatform({this.megabytes, this.error});

  final double? megabytes;
  final Exception? error;
  final asked = <String>[];

  @override
  Future<double?> getFreeDiskSpaceForPath(String path) async {
    asked.add(path);
    if (error != null) throw error!;
    return megabytes;
  }
}

void main() {
  const probe = DiskSpacePlusFreeSpaceProbe();
  late DiskSpacePlusPlatform original;

  setUp(() => original = DiskSpacePlusPlatform.instance);
  tearDown(() => DiskSpacePlusPlatform.instance = original);

  test('convierte los megabytes del complemento a bytes', () async {
    final platform = _FakePlatform(megabytes: 1500);
    DiskSpacePlusPlatform.instance = platform;

    expect(await probe.freeBytesAt('/datos'), 1500 * 1024 * 1024);
    expect(platform.asked, ['/datos']);
  });

  test('redondea hacia abajo: es el error seguro', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform(megabytes: 10.9999999);

    expect(await probe.freeBytesAt('/datos'), lessThan(11 * 1024 * 1024));
  });

  test('sin dato del sistema, «no se sabe»', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform();

    expect(await probe.freeBytesAt('/datos'), isNull);
  });

  test('un valor negativo no es un dato', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform(megabytes: -1);

    expect(await probe.freeBytesAt('/datos'), isNull);
  });

  test('si el complemento no existe en la plataforma, «no se sabe»', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform(
      error: MissingPluginException('sin implementación'),
    );

    expect(await probe.freeBytesAt('/datos'), isNull);
  });

  test('si el sistema falla, «no se sabe»', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform(
      error: PlatformException(code: 'fallo'),
    );

    expect(await probe.freeBytesAt('/datos'), isNull);
  });

  test('un directorio que no existe no rompe: «no se sabe»', () async {
    DiskSpacePlusPlatform.instance = _FakePlatform(
      error: Exception('Specified path does not exist'),
    );

    expect(await probe.freeBytesAt('/no-existe'), isNull);
  });

  test('sin el complemento registrado —escritorio—, «no se sabe»', () async {
    // Sin doble: el canal real, que en las pruebas no tiene a nadie del otro
    // lado, contesta con MissingPluginException.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await probe.freeBytesAt('.'), isNull);
  });
}
