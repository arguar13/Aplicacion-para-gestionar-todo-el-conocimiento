import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';

void main() {
  group('la cara de una voz (F47, paso 3, decisión D)', () {
    test('la misma voz da siempre la misma cara', () {
      final first = VoiceFace.of('vits-piper-es_AR-daniela-high#0', 'Daniela');
      final again = VoiceFace.of('vits-piper-es_AR-daniela-high#0', 'Daniela');
      expect(again, first);
      // Fijada: si cambia la cuenta, cambian las caras que la persona ya
      // conoce.
      expect(first.hue, 210);
      expect(first.initials, 'D');
      expect(first.wave, hasLength(VoiceFace.waveBars));
    });

    test('voces distintas, caras distintas', () {
      final ids = [
        for (var sid = 0; sid < 54; sid++) 'kokoro-int8-multi-lang-v1_0#$sid',
      ];
      final faces = {for (final id in ids) VoiceFace.of(id, 'X')};
      expect(faces, hasLength(ids.length));
      final hues = {for (final face in faces) face.hue};
      expect(hues.length, greaterThan(30));
    });

    test('los rasgos quedan en su rango', () {
      for (var i = 0; i < 200; i++) {
        final face = VoiceFace.of('voz $i', 'Voz');
        expect(face.hue, inInclusiveRange(0, 359));
        expect(face.accentHue, inInclusiveRange(0, 359));
        expect((face.accentHue - face.hue) % 360, inInclusiveRange(40, 159));
        expect(face.tilt, inInclusiveRange(0, 1));
        for (final bar in face.wave) {
          expect(bar, inInclusiveRange(0.25, 1));
        }
      }
    });

    test('las iniciales: dos palabras como mucho, un número tal cual', () {
      expect(initialsOf('Daniela'), 'D');
      expect(initialsOf('Sharvard F'), 'SF');
      expect(initialsOf('northern english male'), 'NE');
      expect(initialsOf('12'), '12');
      expect(initialsOf('Ñandú'), 'Ñ');
      expect(initialsOf('  '), '?');
    });
  });
}
