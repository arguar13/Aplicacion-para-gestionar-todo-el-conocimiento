import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/relations/domain/services/similar_pairs.dart';

/// Los pares que hablan de lo mismo (F44, paso 5, la capa «Parecidos» del
/// Mapa): el coseno entre los centros de los vectores de cada elemento, con
/// sus topes. Es puro: vectores de juguete de tres dimensiones.
void main() {
  List<String> keys(List<SimilarPair> pairs) => [
    for (final pair in pairs) '${pair.a}-${pair.b}',
  ];

  test('el par se ordena solo, y su clave no depende del orden', () {
    final pair = SimilarPair('z', 'a', 0.7);
    expect((pair.a, pair.b), ('a', 'z'));
    expect(pair.key, similarPairKey('z', 'a'));
    expect(similarPairKey('a', 'z'), similarPairKey('z', 'a'));
  });

  test('del más parecido al menos, desde el mínimo, por el centro de sus '
      'vectores y no por el más parecido de ellos', () {
    final pairs = mostSimilarPairs(
      {
        'a': [
          [1, 0, 0],
        ],
        'b': [
          [0.9, 0.1, 0],
        ],
        // Su centro es [0.5, 0.5, 0]: uno de sus vectores es igual al de «a»,
        // pero el par no llega a lo más parecido.
        'c': [
          [1, 0, 0],
          [0, 1, 0],
        ],
        'd': [
          [0, 0, 1],
        ],
      },
      minSimilarity: 0.6,
      perItem: 5,
      limit: 10,
    );

    expect(keys(pairs), ['a-b', 'b-c', 'a-c']);
    expect(pairs.first.score, greaterThan(pairs.last.score));
    expect(pairs.every((pair) => pair.score >= 0.6), isTrue);
  });

  test('sin los pares de «except»: lo ya vinculado no se propone', () {
    final pairs = mostSimilarPairs(
      {
        'a': [
          [1, 0, 0],
        ],
        'b': [
          [1, 0, 0],
        ],
        'c': [
          [0.9, 0.1, 0],
        ],
      },
      minSimilarity: 0.6,
      perItem: 5,
      limit: 10,
      except: {similarPairKey('b', 'a')},
    );

    expect(keys(pairs), ['a-c', 'b-c']);
  });

  test('a lo sumo «perItem» por elemento: uno central no se lleva todas', () {
    // Cinco casi iguales: sin el tope serían diez pares.
    final pairs = mostSimilarPairs(
      {
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          id: [
            [1, id.codeUnitAt(0) / 1000, 0],
          ],
      },
      minSimilarity: 0.6,
      perItem: 2,
      limit: 10,
    );

    final perItem = <String, int>{};
    for (final pair in pairs) {
      perItem
        ..update(pair.a, (n) => n + 1, ifAbsent: () => 1)
        ..update(pair.b, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(perItem.values.every((n) => n <= 2), isTrue);
    expect(pairs.length, inInclusiveRange(4, 5));
  });

  test('a lo sumo «limit» en total', () {
    final pairs = mostSimilarPairs(
      {
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          id: [
            [1, 0, 0],
          ],
      },
      minSimilarity: 0.6,
      perItem: 5,
      limit: 3,
    );

    expect(pairs, hasLength(3));
  });

  test('a igual parecido, por los identificadores: siempre lo mismo', () {
    final vectors = {
      for (final id in ['d', 'b', 'c', 'a'])
        id: [
          [1.0, 0.0, 0.0],
        ],
    };
    final first = mostSimilarPairs(
      vectors,
      minSimilarity: 0.6,
      perItem: 5,
      limit: 10,
    );

    expect(keys(first), ['a-b', 'a-c', 'a-d', 'b-c', 'b-d', 'c-d']);
  });

  test('con vectores de dos modelos, compara los de la dimensión más común; '
      'quien no tiene ninguno de esa no entra', () {
    final pairs = mostSimilarPairs(
      {
        // Tres vectores de tres dimensiones contra dos de dos: la más común
        // es la de tres.
        'a': [
          [1, 0, 0],
          [1, 0, 0],
        ],
        'b': [
          [1, 0, 0],
          [1, 0],
        ],
        'otro': [
          [1, 0],
        ],
      },
      minSimilarity: 0.6,
      perItem: 5,
      limit: 10,
    );

    expect(keys(pairs), ['a-b']);
  });

  test('sin nada que comparar, o con topes en cero, nada', () {
    expect(
      mostSimilarPairs(const {}, minSimilarity: 0, perItem: 2, limit: 5),
      isEmpty,
    );
    final two = {
      'a': [
        [1.0, 0.0],
      ],
      'b': [
        [1.0, 0.0],
      ],
    };
    expect(
      mostSimilarPairs(two, minSimilarity: 0, perItem: 0, limit: 5),
      isEmpty,
    );
    expect(
      mostSimilarPairs(two, minSimilarity: 0, perItem: 2, limit: 0),
      isEmpty,
    );
  });
}
