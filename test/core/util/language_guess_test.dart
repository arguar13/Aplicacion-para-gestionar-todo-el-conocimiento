import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/language_guess.dart';

void main() {
  group('en qué idioma está escrito un texto (F22)', () {
    test('español', () {
      expect(
        guessLanguage(
          'El 85% del universo está hecho de una materia que no vemos. En este '
          'video explicamos cómo se la ha medido y por qué es tan importante.',
        ),
        'es',
      );
    });

    test('inglés', () {
      expect(
        guessLanguage(
          'In this video we explain what the universe is made of, and how we '
          'know that most of it is not what you can see with a telescope.',
        ),
        'en',
      );
    });

    test('portugués', () {
      expect(
        guessLanguage(
          'Neste vídeo nós explicamos o que o universo é feito, e por que '
          'isso não é o que você vê com um telescópio. Muito mais do que os '
          'olhos são capazes.',
        ),
        'pt',
      );
    });

    test('francés, italiano y alemán', () {
      expect(
        guessLanguage(
          'Dans cette vidéo nous expliquons ce que est fait le monde et '
          'pourquoi il est très important pour nous tous.',
        ),
        'fr',
      );
      expect(
        guessLanguage(
          'In questo video spieghiamo che cosa è fatto il mondo e perché è '
          'molto importante per tutti noi, non solo per gli altri.',
        ),
        'it',
      );
      expect(
        guessLanguage(
          'In diesem Video erklären wir, was die Welt ist und warum es nicht '
          'nur für uns wichtig ist, sondern auch für die anderen.',
        ),
        'de',
      );
    });

    test('un título corto no alcanza: ante la duda, nada', () {
      expect(guessLanguage('El 85% del universo'), isNull);
      expect(guessLanguage(''), isNull);
      expect(guessLanguage('NASA JWST 4K'), isNull);
    });

    test('un texto en otro alfabeto no se confunde con uno conocido', () {
      expect(
        guessLanguage('هذا الفيديو يشرح ما هو الكون وكيف نعرف ذلك'),
        isNull,
      );
    });

    test('los enlaces y las direcciones no cuentan', () {
      expect(
        guessLanguage(
          'https://www.the-and-of-to-is-in-that-it.com/the/and/of/to/is/in '
          'www.the-and-of-to-is-in-that-it.com',
        ),
        isNull,
      );
    });

    test('dos idiomas parecidos a la par: no se sabe', () {
      // Palabras que son del español y del portugués por igual.
      expect(guessLanguage('como como como como uma una una uma'), isNull);
    });

    test('solo se mira el comienzo: los créditos del final no cambian el '
        'idioma', () {
      const spanish =
          'En este video explicamos por qué el universo está hecho de una '
          'materia que no vemos, y cómo se lo ha medido en los años. ';
      final credits = 'the and of to is in that it you for with this are ' * 80;
      expect(guessLanguage(spanish + ' ' * 2000 + credits), 'es');
    });
  });
}
