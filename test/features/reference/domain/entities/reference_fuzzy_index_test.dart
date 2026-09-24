import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_fuzzy_index.dart';

void main() {
  group('find', () {
    test('mismo título, mismo año, mismo autor: coincide', () {
      const index = ReferenceFuzzyIndex({
        'cien años de soledad': [
          ReferenceFuzzyCandidate(
            itemId: 'a',
            title: 'Cien años de soledad',
            year: 1967,
            firstAuthorFamily: 'garcia marquez',
          ),
        ],
      });

      final found = index.find(
        title: 'CIEN AÑOS DE SOLEDAD',
        year: 1967,
        authorFamily: 'garcia marquez',
      );

      expect(found, hasLength(1));
      expect(found.single.itemId, 'a');
    });

    test('no distingue mayúsculas ni acentos en el título', () {
      const index = ReferenceFuzzyIndex({
        'cien anos de soledad': [
          ReferenceFuzzyCandidate(itemId: 'a', title: 'Cien Años De Soledad'),
        ],
      });

      expect(index.find(title: 'cien anos de soledad'), hasLength(1));
    });

    test('mismo título pero otro año: no coincide', () {
      const index = ReferenceFuzzyIndex({
        'un titulo': [
          ReferenceFuzzyCandidate(itemId: 'a', title: 'Un título', year: 2000),
        ],
      });

      expect(index.find(title: 'Un título', year: 2001), isEmpty);
    });

    test('mismo título pero otro autor: no coincide', () {
      const index = ReferenceFuzzyIndex({
        'un titulo': [
          ReferenceFuzzyCandidate(
            itemId: 'a',
            title: 'Un título',
            firstAuthorFamily: 'garcia',
          ),
        ],
      });

      expect(index.find(title: 'Un título', authorFamily: 'perez'), isEmpty);
    });

    test('sin año de un lado, no descarta —dato ausente no es distinto—', () {
      const index = ReferenceFuzzyIndex({
        'un titulo': [ReferenceFuzzyCandidate(itemId: 'a', title: 'Un título')],
      });

      expect(index.find(title: 'Un título', year: 2020), hasLength(1));
    });

    test('sin autor de un lado, no descarta', () {
      const index = ReferenceFuzzyIndex({
        'un titulo': [
          ReferenceFuzzyCandidate(
            itemId: 'a',
            title: 'Un título',
            firstAuthorFamily: 'garcia',
          ),
        ],
      });

      expect(index.find(title: 'Un título'), hasLength(1));
    });

    test('un título que no está en el índice: vacío, sin romper', () {
      const index = ReferenceFuzzyIndex({});

      expect(index.find(title: 'Nada de esto existe'), isEmpty);
    });

    test('título vacío: vacío, sin romper', () {
      const index = ReferenceFuzzyIndex({});

      expect(index.find(title: ''), isEmpty);
    });
  });
}
