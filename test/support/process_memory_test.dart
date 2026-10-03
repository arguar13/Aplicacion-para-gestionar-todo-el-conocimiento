import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'rss_sampler.dart';

/// El medidor tiene que ver la memoria nueva: si la privada comprometida no
/// creciera con lo que se pide, las pruebas que afirman "no pasó entero por
/// la memoria" pasarían siempre, sin probar nada.
void main() {
  for (final measure in MemoryMeasure.values) {
    test('${measure.name}: ve 96 MB pedidos y usados', () async {
      const size = 96 * 1024 * 1024;
      final sampler = await RssSampler.start(measure: measure);
      final block = Uint8List(size);
      // Se escribe una página de cada 4 KB: memoria pedida pero sin tocar no
      // siempre se compromete.
      for (var i = 0; i < size; i += 4096) {
        block[i] = 1;
      }
      final growth = await sampler.stop();

      expect(block.last, 0);
      expect(
        growth,
        greaterThan(size * 9 ~/ 10),
        reason: 'creció ${growth ~/ 1048576} MB',
      );
    });
  }
}
