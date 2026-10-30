import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/services/flutter_tts_service.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/read_aloud_speed.dart';

void main() {
  group('la regla de la velocidad (decisión H)', () {
    test('va de 0,5× a 3×, sin candados', () {
      expect(readAloudMinSpeed, 0.5);
      expect(readAloudMaxSpeed, 3.0);
      expect(readAloudSpeedPresets, [1.0, 1.2, 1.5, 2.0, 3.0]);
    });

    test('lleva a la décima más cercana, exacta', () {
      expect(snapReadAloudSpeed(1.24), 1.2);
      expect(snapReadAloudSpeed(1.26), 1.3);
      expect(snapReadAloudSpeed(12 * 0.1), 1.2);
      expect(snapReadAloudSpeed(1.1 + 0.1), 1.2);
    });

    test('no se sale de los límites', () {
      expect(snapReadAloudSpeed(0.1), 0.5);
      expect(snapReadAloudSpeed(9), 3.0);
      expect(snapReadAloudSpeed(2.96), 3.0);
    });
  });

  group('lo que se le pide a flutter_tts en cada plataforma', () {
    double rate(double speed, TargetPlatform platform, {bool web = false}) =>
        flutterTtsRate(speed, platform: platform, web: web);

    test('en Android, la mitad, hasta 3×', () {
      expect(rate(1, TargetPlatform.android), 0.5);
      expect(rate(0.5, TargetPlatform.android), 0.25);
      expect(rate(3, TargetPlatform.android), 1.5);
      expect(rate(4, TargetPlatform.android), 1.5);
    });

    test('en Windows, medio menos: su motor le suma medio', () {
      expect(rate(1, TargetPlatform.windows), 0.5);
      expect(rate(0.5, TargetPlatform.windows), 0);
      expect(rate(3, TargetPlatform.windows), 2.5);
    });

    test('en la web, tal cual', () {
      expect(rate(1, TargetPlatform.android, web: true), 1);
      expect(rate(3, TargetPlatform.windows, web: true), 3);
    });

    test('en iOS, la mitad, con su techo en 1', () {
      expect(rate(1, TargetPlatform.iOS), 0.5);
      expect(rate(3, TargetPlatform.iOS), 1);
    });
  });
}
