import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/data/on_device/device_probe.dart';

const _meminfo = '''
MemTotal:       11718604 kB
MemFree:          512344 kB
MemAvailable:    4380012 kB
''';

const _features =
    'fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid '
    'asimdrdm lrcpc dcpop asimddp sha512 asimdfhm';

/// Lo que dice un Dimensity 7200: los ocho núcleos con producto punto y
/// media precisión.
final _cpuinfo = [
  for (var i = 0; i < 8; i++) ...[
    'processor\t: $i',
    'BogoMIPS\t: 26.00',
    'Features\t: $_features',
    '',
  ],
].join('\n');

void main() {
  test('MemTotal en bytes; sin la línea, no se sabe', () {
    expect(memTotalBytes(_meminfo), 11718604 * 1024);
    expect(memTotalBytes('MemFree: 1 kB'), isNull);
    expect(memTotalBytes(null), isNull);
    expect(memTotalBytes('MemTotal: 0 kB'), isNull);
  });

  test('el procesador sirve si todos sus núcleos tienen producto punto y '
      'media precisión', () {
    expect(cpuFeaturesSupported(_cpuinfo), isTrue);
    // Con `fphp` sin `asimdhp` también.
    expect(cpuFeaturesSupported('Features : fp asimd asimddp fphp'), isTrue);
    // Un núcleo viejo (Cortex-A53, sin asimddp) alcanza para que no.
    expect(
      cpuFeaturesSupported(
        '$_cpuinfo\nprocessor : 8\nFeatures : fp asimd evtstrm crc32 cpuid',
      ),
      isFalse,
    );
    expect(cpuFeaturesSupported('Features : fp asimd asimdhp'), isFalse);
    expect(cpuFeaturesSupported('processor : 0'), isNull);
    expect(cpuFeaturesSupported(null), isNull);
  });

  group('SystemDeviceProbe', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('sondeo_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, String content) {
      final file = File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync(content);
      return file.path;
    }

    test('en Android lee la memoria, el procesador y el lugar libre', () async {
      final probe = SystemDeviceProbe(
        freeBytes: () async => 42,
        meminfo: write('meminfo', _meminfo),
        cpuinfo: write('cpuinfo', _cpuinfo),
        android: true,
        abi: Abi.androidArm64,
      );
      final profile = await probe.read();
      expect(profile.android, isTrue);
      expect(profile.arm64, isTrue);
      expect(profile.cpuSupported, isTrue);
      expect(profile.ramGb, 12);
      expect(profile.freeStorageBytes, 42);
    });

    test(
      'lo que no puede leer queda sin saber; ARM de 32 bits no es arm64',
      () async {
        final probe = SystemDeviceProbe(
          freeBytes: () async => throw const FileSystemException('sin lugar'),
          meminfo: '${dir.path}/no-esta',
          cpuinfo: '${dir.path}/tampoco',
          android: true,
          abi: Abi.androidArm,
        );
        final profile = await probe.read();
        expect(profile.arm64, isFalse);
        expect(profile.cpuSupported, isNull);
        expect(profile.totalRamBytes, isNull);
        expect(profile.freeStorageBytes, isNull);
      },
    );

    test('fuera de Android no lee nada', () async {
      var asked = false;
      final probe = SystemDeviceProbe(
        freeBytes: () async {
          asked = true;
          return 1;
        },
        android: false,
      );
      final profile = await probe.read();
      expect(profile.android, isFalse);
      expect(profile.arm64, isFalse);
      expect(asked, isFalse);
    });
  });
}
