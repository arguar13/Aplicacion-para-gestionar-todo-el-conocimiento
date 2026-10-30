import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/text_script.dart';
import 'package:sinapsis/features/transform/domain/services/video_text_language.dart';

/// La red de seguridad del idioma del texto de un video (F45, paso 4): lo que
/// no está en el idioma que se habla no se guarda.
void main() {
  const title =
      'Las reliquias de San Francisco de Asís que han fascinado al mundo';

  /// Lo que vio el dueño: la transcripción, con sus marcas de tiempo, de un
  /// video en español, escrita en árabe.
  const arabic =
      '[0:00] بقايا القديس فرنسيس الأسيزي التي أذهلت العالم\n'
      '[0:07] في هذا الفيديو نتحدث عن تاريخ هذه الآثار المقدسة\n'
      '[0:15] وكيف وصلت إلينا عبر القرون';

  const spanish =
      '[0:00] Las reliquias de San Francisco de Asís han fascinado al mundo\n'
      '[0:07] y en este video vamos a ver por qué son tan importantes para '
      'los fieles\n'
      '[0:15] y cómo se conservan desde hace más de ochocientos años en la '
      'basílica.';

  const english =
      "[0:00] In this video we're going to talk about the history of the "
      'relics\n'
      '[0:07] and how they have been kept for more than eight hundred years in '
      'the basilica.';

  group('el texto de un video, contra el idioma que se habla', () {
    test('árabe en un video en español: otro idioma, que se reconoce por su '
        'escritura', () {
      expect(
        checkVideoText(arabic, spoken: 'es', title: title),
        const VideoTextForeign(
          script: TextScript.arabic,
          language: 'ar',
          spoken: 'es',
        ),
      );
    });

    test('sin saber qué se habla, el título en latín alcanza para rechazar '
        'el árabe', () {
      expect(
        checkVideoText(arabic, title: title),
        const VideoTextForeign(script: TextScript.arabic, language: 'ar'),
      );
    });

    test('inglés con subtítulos en inglés: está en su idioma', () {
      expect(
        checkVideoText(english, spoken: 'en', title: 'The relics of Assisi'),
        const VideoTextFits(),
      );
    });

    test('español en un video en español, también con región', () {
      expect(checkVideoText(spanish, spoken: 'es-419'), const VideoTextFits());
    });

    test('una traducción al inglés de un video en español: otro idioma, '
        'por sus palabras', () {
      expect(
        checkVideoText(english, spoken: 'es', title: title),
        const VideoTextForeign(
          script: TextScript.latin,
          language: 'en',
          spoken: 'es',
        ),
      );
    });

    test('un video que mezcla dos idiomas no se rechaza: ni español con '
        'inglés, ni español que cita en árabe', () {
      const mixed =
          '[0:00] Hola a todos, hoy hablamos con nuestro invitado sobre el '
          'trabajo.\n'
          '[0:05] Thank you, it is a pleasure to be here with you.\n'
          '[0:10] Él nos va a contar cómo es el trabajo en su país y por qué '
          'lo eligió.\n'
          "[0:15] Well, the work is hard, but it's what we love.";
      expect(checkVideoText(mixed, spoken: 'es'), const VideoTextFits());
      expect(checkVideoText(mixed, spoken: 'en'), const VideoTextFits());

      const quoting =
          '$spanish\n[0:30] La inscripción dice: بسم الله الرحمن الرحيم';
      expect(checkVideoText(quoting, spoken: 'es'), const VideoTextFits());
    });

    test('un video corto o casi sin habla no se juzga', () {
      const short = '[0:00] [Música]\n[0:04] مرحبا\n[0:06] [Aplausos]';
      expect(
        checkVideoText(short, spoken: 'es', title: title),
        const VideoTextUnsure(),
      );
    });

    test('sin saber qué se habla y con un título que no dice nada, no se '
        'juzga', () {
      expect(checkVideoText(arabic, title: '#42'), const VideoTextUnsure());
    });

    test('un idioma de una escritura que no se cuenta no se compara', () {
      expect(checkVideoText(arabic, spoken: 'hy'), const VideoTextUnsure());
    });

    test('un idioma que la app no reconoce por sus palabras se juzga solo por '
        'su escritura', () {
      expect(checkVideoText(spanish, spoken: 'tr'), const VideoTextFits());
      expect(
        checkVideoText(arabic, spoken: 'tr'),
        const VideoTextForeign(
          script: TextScript.arabic,
          language: 'ar',
          spoken: 'tr',
        ),
      );
    });

    test('las marcas de tiempo, lo que va entre corchetes y los enlaces no '
        'cuentan como habla', () {
      expect(
        spokenWordsOf('[3:15] hola [Música] https://ejemplo.com/a fin').trim(),
        matches(RegExp(r'^hola\s+fin$')),
      );
    });
  });

  group('qué idioma se habla, para juzgar y para transcribir', () {
    test('el que eligió la persona manda, aunque YouTube diga otro', () {
      expect(
        expectedVideoLanguage(chosen: 'pt', detected: 'es', title: title),
        'pt',
      );
    });

    test('un idioma guardado por una versión anterior —el de la pista que '
        'bajó, árabe— no manda: vale el que dijo YouTube si coincide con el '
        'título', () {
      expect(
        expectedVideoLanguage(chosen: 'ar', detected: 'es', title: title),
        'es',
      );
    });

    test('si YouTube también dice árabe —su audio «de siempre» era un '
        'doblaje—, el título y la descripción dicen el idioma', () {
      expect(
        expectedVideoLanguage(
          chosen: 'ar',
          detected: 'ar',
          title: title,
          description:
              'En este video les contamos la historia de las reliquias del '
              'santo, que están en la basílica de Asís desde hace siglos. Es '
              'una de las más visitadas del mundo, con miles de peregrinos '
              'por año.',
        ),
        'es',
      );
      // Sin descripción que lo diga, no se sabe: se transcribe en el idioma
      // de quien usa la app.
      expect(expectedVideoLanguage(detected: 'ar', title: title), isNull);
    });

    test('un video en árabe de verdad, con su título en árabe, sigue en '
        'árabe', () {
      expect(
        expectedVideoLanguage(
          detected: 'ar',
          title: 'بقايا القديس فرنسيس الأسيزي',
        ),
        'ar',
      );
      // Sin ninguna pista, lo que dice la escritura del título.
      expect(expectedVideoLanguage(title: 'بقايا القديس فرنسيس الأسيزي'), 'ar');
    });

    test('con un título que no dice nada, la pista de YouTube vale', () {
      expect(expectedVideoLanguage(detected: 'ar', title: '#42'), 'ar');
      expect(expectedVideoLanguage(title: '#42'), isNull);
    });
  });
}
