import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/domain/voices/passage_languages.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_locale.dart';

void main() {
  group('el idioma de un pasaje (F47, paso 3)', () {
    test('una oración, por sus palabras o por su escritura', () {
      expect(
        languageOfPassage(
          'El perro de la casa está en el jardín con los chicos.',
        ),
        'es',
      );
      expect(
        languageOfPassage('The dog is in the garden with the children.'),
        'en',
      );
      expect(languageOfPassage('Собака находится в саду с детьми.'), 'ru');
      expect(languageOfPassage('यह एक छोटा सा वाक्य है'), 'hi');
      expect(languageOfPassage('今天天气很好，我们去公园吧'), 'zh');
      expect(languageOfPassage('今日はいい天気ですね'), 'ja');
    });

    test('ante la duda, ninguno', () {
      expect(languageOfPassage('Capítulo 2'), isNull);
      expect(languageOfPassage('L00 L01 L02'), isNull);
      expect(languageOfPassage('Привет and hello, mixed здесь text'), isNull);
    });
  });

  group('el idioma de cada pedazo de lo que se lee (F47, paso 3)', () {
    // Un texto en español, con una cita en inglés de dos oraciones.
    const text =
        'La historia de la ciudad es larga, y los que la cuentan son muchos.\n'
        'Capítulo 2\n'
        'Los primeros habitantes llegaron por el río con sus familias.\n'
        'As the old saying goes, the river is the road of the people.\n'
        'Fin\n'
        'And the people of the river were the first to build it.\n'
        'Después vinieron los demás, con lo que tenían en las manos.\n'
        'Con el tiempo, el pueblo se hizo ciudad y la ciudad, su capital.\n'
        'Hoy es una de las más grandes del país, y también una de las más '
        'viejas.';
    final segments = buildReadableSegments(text, sourceKey: 'texto');

    test('cada parte con su idioma, y lo que no se reconoce, del documento o '
        'de los dos lados', () {
      final languages = PassageLanguages.of(segments);
      expect(languages.document, 'es');
      expect(
        [for (var i = 0; i < segments.length; i++) languages.at(i)],
        [
          'es',
          'es', // «Capítulo 2»: del documento.
          'es',
          'en',
          'en', // «Fin», entre dos en inglés.
          'en',
          'es',
          'es',
          'es',
        ],
      );
    });

    test('se recuerda por lista de pedazos', () {
      expect(
        identical(PassageLanguages.of(segments), PassageLanguages.of(segments)),
        isTrue,
      );
    });

    test('un texto que no se reconoce no tiene idioma', () {
      final words = buildReadableSegments(
        'L00 L01 L02\nL10 L11 L12',
        sourceKey: 'palabras',
      );
      final languages = PassageLanguages.of(words);
      expect(languages.document, isNull);
      expect(languages.at(0), isNull);
    });
  });

  group('el acento (F47, paso 3)', () {
    test('la región y su bandera', () {
      expect(accentRegion('es_ar'), 'AR');
      expect(accentRegion('es'), isNull);
      expect(accentFlag('es-AR'), '🇦🇷');
      expect(accentFlag('en-GB'), '🇬🇧');
      expect(accentFlag('es'), isNull);
      expect(accentFlag('es-419'), isNull);
    });
  });
}
