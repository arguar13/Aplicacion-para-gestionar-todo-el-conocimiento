import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_description.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

void main() {
  const start = VoiceDesign(locale: 'en-US');

  group('interpretVoiceDescription', () {
    test('el ejemplo del plan: hombre joven, rioplatense, cálido y '
        'entusiasta', () {
      final described = interpretVoiceDescription(
        'Hombre joven, rioplatense, cálido y entusiasta, como un relator de '
        'fútbol',
        start,
      );
      expect(described.design.gender, VoiceGender.male);
      expect(described.design.age, VoiceAge.young);
      // Dos estilos: vale el último que se nombra.
      expect(described.design.style, VoiceStyle.energetic);
      expect(described.design.locale, 'es');
      expect(described.accent, 'es-AR');
      expect(described.understood, [
        'hombre',
        'joven',
        'rioplatense',
        'cálido',
        'entusiasta',
        'relator',
      ]);
    });

    test('lo que no se nombra queda como estaba', () {
      const current = VoiceDesign(
        locale: 'fr-FR',
        timbre: VoiceTimbre.velvety,
        pace: 1.1,
      );
      final described = interpretVoiceDescription('una mujer serena', current);
      expect(described.design.gender, VoiceGender.female);
      expect(described.design.style, VoiceStyle.calm);
      expect(described.design.locale, 'fr-FR');
      expect(described.design.timbre, VoiceTimbre.velvety);
      expect(described.design.pace, 1.1);
      expect(described.accent, isNull);
    });

    test('entiende dos palabras juntas, en inglés también', () {
      final described = interpretVoiceDescription(
        'Middle aged woman with a deep voice, british, slow',
        start,
      );
      expect(described.design.age, VoiceAge.adult);
      expect(described.design.gender, VoiceGender.female);
      expect(described.design.timbre, VoiceTimbre.deep);
      expect(described.design.locale, 'en-GB');
      expect(described.design.pace, 0.88);
      expect(described.understood, contains('middle aged'));
      expect(described.understood, contains('deep voice'));
    });

    test('«con autoridad» y el ritmo rápido', () {
      final described = interpretVoiceDescription(
        'Voz firme, con autoridad, rápida',
        start,
      );
      expect(described.design.style, VoiceStyle.authoritative);
      expect(described.design.pace, 1.15);
    });

    test('sin palabras conocidas, nada cambia', () {
      final described = interpretVoiceDescription('algo lindo', start);
      expect(described.design, start);
      expect(described.understood, isEmpty);
    });
  });

  group('checkRealPerson', () {
    test('un oficio, sin nombre, pasa', () {
      expect(
        checkRealPerson(
          'Hombre joven, rioplatense, cálido y entusiasta, como un relator de '
          'fútbol.',
        ).found,
        isFalse,
      );
      expect(
        checkRealPerson(
          'Voz de mujer, en inglés británico. Cálida y serena.',
        ).found,
        isFalse,
      );
      expect(
        checkRealPerson(
          'Grave, como una locutora de radio de Buenos Aires.',
        ).found,
        isFalse,
      );
      expect(
        checkRealPerson('Deep British voice, calm, like a narrator.').found,
        isFalse,
      );
    });

    test('un nombre propio después de «como» no pasa', () {
      final finding = checkRealPerson('Enérgico, como Messi');
      expect(finding.found, isTrue);
      expect(finding.names, contains('Messi'));
    });

    test('nombre y apellido, aunque empiecen la descripción', () {
      final finding = checkRealPerson('Morgan Freeman, grave y sereno');
      expect(finding.names, contains('Freeman'));
    });

    test('«la voz de» alguien, con nombre o sin él, no pasa', () {
      expect(
        checkRealPerson('La voz de Juan Pérez').names,
        contains('Juan Pérez'),
      );
      expect(checkRealPerson('la voz de mi abuela').found, isTrue);
      expect(checkRealPerson('la voz de un locutor').found, isFalse);
    });

    test('los pedidos de imitar, en minúscula también', () {
      expect(checkRealPerson('imitando a mi profesor').found, isTrue);
      expect(checkRealPerson('que suene como messi').found, isTrue);
      expect(checkRealPerson('it sounds like a famous actor').found, isTrue);
      expect(checkRealPerson('impersonate the president').found, isTrue);
      expect(checkRealPerson('parecida a Shakira').found, isTrue);
      expect(
        checkRealPerson('parecida a una cantante de tango').found,
        isFalse,
      );
    });
  });
}
