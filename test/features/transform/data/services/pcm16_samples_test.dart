import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/transform/data/services/pcm16_samples.dart';

void main() {
  group('pcm16ToFloat32Samples', () {
    test('sin cabecera, convierte cada par de bytes en una muestra', () {
      // 0 → 0.0, el máximo positivo (32767) → casi 1.0, el mínimo (-32768,
      // 0x8000) → exactamente -1.0.
      final bytes = Uint8List.fromList([
        0x00, 0x00, // 0
        0xFF, 0x7F, // 32767
        0x00, 0x80, // -32768
      ]);

      final samples = pcm16ToFloat32Samples(bytes);

      expect(samples, hasLength(3));
      expect(samples[0], 0.0);
      expect(samples[1], closeTo(1.0, 0.001));
      expect(samples[2], -1.0);
    });

    test('saltea la cabecera cuando se le indica cuánto mide', () {
      final bytes = Uint8List.fromList([
        // 44 bytes de "cabecera" que no son datos de audio.
        for (var i = 0; i < 44; i++) 0xAA,
        0x00, 0x40, // 16384 → 0.5
      ]);

      final samples = pcm16ToFloat32Samples(bytes, headerBytes: 44);

      expect(samples, hasLength(1));
      expect(samples[0], closeTo(0.5, 0.001));
    });

    test('sin datos después de la cabecera, no hay ninguna muestra', () {
      final bytes = Uint8List(44);

      final samples = pcm16ToFloat32Samples(bytes, headerBytes: 44);

      expect(samples, isEmpty);
    });

    test('lee en little-endian, no en big-endian', () {
      // El byte bajo primero: 0x00 + (0x01 << 8) = 256. Leído al revés, en
      // big-endian, daría 1 en lugar de 256.
      final bytes = Uint8List.fromList([0x00, 0x01]);

      final samples = pcm16ToFloat32Samples(bytes);

      expect(samples[0], closeTo(256 / 32768.0, 1e-9));
    });
  });
}
