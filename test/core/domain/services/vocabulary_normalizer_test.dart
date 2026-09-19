import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

// Las formas descompuestas se arman por código y no se escriben en literal:
// en el fuente, "o" + acento combinante se vería idéntica a "ó", y un test
// que dice probar la forma descompuesta podría estar probando la compuesta
// sin que nadie lo note.
final _acute = String.fromCharCode(0x0301);
final _diaeresis = String.fromCharCode(0x0308);
final _tilde = String.fromCharCode(0x0303);
final _cedilla = String.fromCharCode(0x0327);
final _nbsp = String.fromCharCode(0x00A0);

void main() {
  group('normalizeVocabularyLabel', () {
    test('no distingue mayúsculas', () {
      expect(normalizeVocabularyLabel('Bizancio'), 'bizancio');
      expect(normalizeVocabularyLabel('BIZANCIO'), 'bizancio');
      expect(normalizeVocabularyLabel('bizancio'), 'bizancio');
    });

    test('no distingue acentos', () {
      expect(normalizeVocabularyLabel('Canción'), 'cancion');
      expect(normalizeVocabularyLabel('cancion'), 'cancion');
      expect(normalizeVocabularyLabel('CANCIÓN'), 'cancion');
      expect(normalizeVocabularyLabel('Pingüino'), 'pinguino');
    });

    test(
      'pliega cada vocal acentuada de la lista, en las dos capitalizaciones',
      () {
        expect(normalizeVocabularyLabel('áàâäã'), 'aaaaa');
        expect(normalizeVocabularyLabel('éèêë'), 'eeee');
        expect(normalizeVocabularyLabel('íìîï'), 'iiii');
        expect(normalizeVocabularyLabel('óòôöõ'), 'ooooo');
        expect(normalizeVocabularyLabel('úùûü'), 'uuuu');
        expect(normalizeVocabularyLabel('ýÿ'), 'yy');
        expect(
          normalizeVocabularyLabel('ÁÀÂÄÃÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÝ'),
          'aaaaaeeeeiiiiooooouuuuy',
        );
      },
    );

    test('la eñe y la ce con cedilla son letras propias: no se pliegan', () {
      expect(normalizeVocabularyLabel('Año'), 'año');
      expect(
        normalizeVocabularyLabel('Año'),
        isNot(normalizeVocabularyLabel('Ano')),
      );
      expect(normalizeVocabularyLabel('Curaçao'), 'curaçao');
      expect(normalizeVocabularyLabel('CURAÇAO'), 'curaçao');
      expect(
        normalizeVocabularyLabel('Curaçao'),
        isNot(normalizeVocabularyLabel('Curacao')),
      );
    });

    test('recorta y colapsa los espacios', () {
      expect(normalizeVocabularyLabel('  Roma   antigua \n'), 'roma antigua');
      expect(normalizeVocabularyLabel('Roma\t\tantigua'), 'roma antigua');
      // Espacio de no separación, que llega al copiar de páginas web.
      expect(normalizeVocabularyLabel('Roma${_nbsp}antigua'), 'roma antigua');
    });

    test('un texto vacío o solo de espacios normaliza a vacío', () {
      expect(normalizeVocabularyLabel(''), '');
      expect(normalizeVocabularyLabel('   \n\t '), '');
    });

    test('la puntuación cuenta: no se descarta', () {
      expect(normalizeVocabularyLabel('S. XX'), 's. xx');
      expect(
        normalizeVocabularyLabel('S. XX'),
        isNot(normalizeVocabularyLabel('SXX')),
      );
      expect(normalizeVocabularyLabel('C++'), 'c++');
    });

    test('dos palabras distintas siguen siendo distintas', () {
      expect(
        normalizeVocabularyLabel('Roma'),
        isNot(normalizeVocabularyLabel('Rome')),
      );
      expect(
        normalizeVocabularyLabel('Historia'),
        isNot(normalizeVocabularyLabel('Histeria')),
      );
    });

    group('texto en forma descompuesta (letra + marca combinante)', () {
      test('las formas descompuestas de verdad son otro texto', () {
        // La premisa de este grupo: si fueran el mismo texto que la forma
        // compuesta, nada de lo que sigue probaría nada.
        expect('Cancio${_acute}n', isNot('Canción'));
        expect('An${_tilde}o', isNot('Año'));
      });

      test('los acentos sueltos se descartan', () {
        expect(normalizeVocabularyLabel('Cancio${_acute}n'), 'cancion');
        expect(normalizeVocabularyLabel('Pingu${_diaeresis}ino'), 'pinguino');
      });

      test('la eñe y la ce con cedilla se recomponen y se conservan', () {
        expect(normalizeVocabularyLabel('An${_tilde}o'), 'año');
        expect(normalizeVocabularyLabel('AN${_tilde}O'), 'año');
        expect(normalizeVocabularyLabel('Curac${_cedilla}ao'), 'curaçao');
        expect(normalizeVocabularyLabel('CURAC${_cedilla}AO'), 'curaçao');
      });

      test('da lo mismo que la forma compuesta', () {
        expect(
          normalizeVocabularyLabel('Cancio${_acute}n'),
          normalizeVocabularyLabel('Canción'),
        );
        expect(
          normalizeVocabularyLabel('An${_tilde}o'),
          normalizeVocabularyLabel('Año'),
        );
        expect(
          normalizeVocabularyLabel('Curac${_cedilla}ao'),
          normalizeVocabularyLabel('Curaçao'),
        );
      });
    });

    test('es idempotente', () {
      for (final label in [
        'Canción',
        '  Año   nuevo ',
        'S. XX',
        'CURAÇAO',
        'An${_tilde}o',
        'Cancio${_acute}n',
        '',
      ]) {
        final once = normalizeVocabularyLabel(label);
        expect(normalizeVocabularyLabel(once), once, reason: 'con "$label"');
      }
    });

    test('deja intactas las letras de otros alfabetos', () {
      // Solo pasan a minúscula: el plegado de acentos es el de la lista.
      expect(normalizeVocabularyLabel('Ελλάδα'), 'ελλάδα');
      expect(normalizeVocabularyLabel('東京'), '東京');
      expect(normalizeVocabularyLabel('Москва'), 'москва');
    });
  });
}
