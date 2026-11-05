import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/processed/domain/services/headings/heading_text.dart';

/// Lo que comparten los lectores de títulos del Índice (F46, paso 1): los
/// niveles corridos, el título como se lee y la forma de compararlo.
void main() {
  group('runningLevels: los niveles corridos', () {
    test('un h1 seguido de un h3 queda en 1 y 2: el salto no deja un nivel '
        'vacío', () {
      expect(runningLevels([1, 3]), [1, 2]);
      expect(runningLevels([1, 3, 3, 1, 4]), [1, 2, 2, 1, 2]);
    });

    test('un documento que empieza en ### empieza en 1', () {
      expect(runningLevels([3, 4, 4, 3]), [1, 2, 2, 1]);
    });

    test('dos que saltan distinto debajo del mismo padre quedan hermanos', () {
      // ## › #### › ###: los dos cuelgan del ##.
      expect(runningLevels([2, 4, 3]), [1, 2, 2]);
    });

    test('uno menos hondo que el primero sube a 1, y lo que sigue cuelga de '
        'él', () {
      expect(runningLevels([3, 2, 3, 1, 2]), [1, 1, 2, 1, 2]);
    });

    test('los niveles que ya eran seguidos quedan como estaban', () {
      expect(runningLevels([1, 2, 3, 2, 3, 1]), [1, 2, 3, 2, 3, 1]);
    });

    test('nada, nada', () {
      expect(runningLevels(const []), isEmpty);
    });
  });

  group('plainHeadingText: el título como se lee', () {
    test('sin negrita, cursiva, tachado ni código', () {
      expect(
        plainHeadingText('**El** _origen_ de ~~todo~~ `Roma`'),
        'El origen de todo Roma',
      );
    });

    test('los guiones bajos de adentro de una palabra quedan', () {
      expect(plainHeadingText('La variable var_uno'), 'La variable var_uno');
      expect(plainHeadingText('__Fuerte__ y _débil_'), 'Fuerte y débil');
    });

    test('un enlace es su texto, y una imagen su texto alternativo', () {
      expect(
        plainHeadingText(
          'Ver [la batalla](https://x.org/a) y ![el mapa](m.png)',
        ),
        'Ver la batalla y el mapa',
      );
      expect(plainHeadingText('Ver [Roma][1]'), 'Ver Roma');
    });

    test('sin etiquetas ni llamadas a notas al pie; un <br> es un espacio', () {
      expect(
        plainHeadingText('El <em>Senado</em>[^3] y el<br/>pueblo'),
        'El Senado y el pueblo',
      );
      expect(plainHeadingText('Uno<BR>dos < tres'), 'Uno dos < tres');
    });

    test('lo escapado y las entidades son lo que escriben', () {
      expect(
        plainHeadingText(r'El \*asterisco\* y el \#'),
        'El *asterisco* y el #',
      );
      expect(
        plainHeadingText('Roma &amp; Cartago &#8212; &#x41;&lt;&gt;&nbsp;fin'),
        'Roma & Cartago — A<> fin',
      );
      expect(plainHeadingText('&nada; &#0;'), '&nada; &#0;');
    });

    test('los espacios y renglones, uno solo', () {
      expect(
        plainHeadingText('  La   caída \n del\timperio  '),
        'La caída del imperio',
      );
    });
  });

  group('hasReadableText', () {
    test('al menos una letra o un número', () {
      expect(hasReadableText('Roma'), isTrue);
      expect(hasReadableText('3'), isTrue);
      expect(hasReadableText('***'), isFalse);
      expect(hasReadableText(' · · · '), isFalse);
      expect(hasReadableText(''), isFalse);
    });
  });

  group('headingKey: la forma de comparar dos títulos', () {
    test('sin mayúsculas, acentos ni puntuación', () {
      expect(headingKey('Capítulo 1: El origen'), 'capitulo 1 el origen');
      expect(headingKey('CAPÍTULO 1 — EL ORIGEN'), 'capitulo 1 el origen');
      expect(headingKey('Capítulo 1\nEl origen'), 'capitulo 1 el origen');
    });

    test('un acento escrito como letra y marca aparte es el mismo', () {
      expect(headingKey('Capítulo'), headingKey('Capítulo'));
    });

    test('la ñ y la ç, como el índice de la búsqueda', () {
      expect(headingKey('Año Façade'), 'ano facade');
    });

    test('sin palabras, vacío', () {
      expect(headingKey(' — · '), '');
    });
  });
}
