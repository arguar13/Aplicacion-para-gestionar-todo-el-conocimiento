import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/index/domain/services/index_match.dart';

/// Lo que se resalta y lo que coincide en el buscador del Índice (F46, paso
/// 3): como lo lee el índice de texto de la base, sin mayúsculas ni acentos,
/// y con el comienzo de cada palabra.
void main() {
  /// Lo resaltado de [title], como texto.
  List<String> marked(String title, String query) => [
    for (final r in indexMatchRanges(title, query))
      title.substring(r.start, r.end),
  ];

  group('las palabras de lo buscado', () {
    test('sin mayúsculas, sin acentos y cortadas donde no hay letra', () {
      expect(indexQueryWords('  Nicéa, 325 — ÁGORA  '), [
        'nicea',
        '325',
        'agora',
      ]);
    });

    test('la ñ se lee como n, como en la base', () {
      expect(indexQueryWords('Ñandú'), ['nandu']);
    });

    test('nada que buscar en solo signos', () {
      expect(indexQueryWords(' — ¿? '), isEmpty);
    });
  });

  group('si un título coincide', () {
    test('todas las palabras, cada una por su comienzo', () {
      expect(
        indexTitleMatches('El Concilio de Nicea (325)', 'nic conc'),
        isTrue,
      );
      expect(indexTitleMatches('El Concilio de Nicea', 'nicea roma'), isFalse);
    });

    test('el comienzo, no el medio de una palabra', () {
      expect(indexTitleMatches('Constantinopla', 'tinopla'), isFalse);
    });

    test('sin acentos ni mayúsculas, de los dos lados', () {
      expect(
        indexTitleMatches('Revolución FRANCESA', 'revolucion fran'),
        isTrue,
      );
      expect(indexTitleMatches('Revolucion', 'Revolución'), isTrue);
    });

    test('sin palabras no coincide nada', () {
      expect(indexTitleMatches('Roma', '  '), isFalse);
    });
  });

  group('lo resaltado', () {
    test('el comienzo de cada palabra que empieza con lo buscado, como está '
        'escrito', () {
      expect(marked('El Concilio de Nicéa', 'conc nicea'), ['Conc', 'Nicéa']);
    });

    test('la más larga que le cabe a cada palabra', () {
      expect(marked('Constantino', 'co cons constan'), ['Constan']);
    });

    test('cada palabra que coincide, aunque se repita', () {
      expect(marked('Roma y la roma de Rómulo', 'rom'), ['Rom', 'rom', 'Róm']);
    });

    test('lo que no coincide no se marca', () {
      expect(indexMatchRanges('El Concilio', 'nicea'), isEmpty);
      expect(indexMatchRanges('El Concilio', ''), isEmpty);
    });

    test('se mide en el texto como está: un emoji antes no corre el tramo', () {
      const title = '🏛️ Roma';
      expect(marked(title, 'roma'), ['Roma']);
    });
  });
}
