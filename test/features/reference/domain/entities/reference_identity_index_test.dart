import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/reference/domain/entities/reference_identity_index.dart';

void main() {
  const index = ReferenceIdentityIndex(
    byDoi: {'10.1000/xyz': 'item-doi'},
    byIsbn: {'9780306406157': 'item-isbn'},
    byUrl: {'https://ejemplo.org': 'item-url'},
  );

  group('find', () {
    test('encuentra por DOI', () {
      expect(index.find(doi: '10.1000/xyz'), 'item-doi');
    });

    test('encuentra por ISBN', () {
      expect(index.find(isbn: '9780306406157'), 'item-isbn');
    });

    test('encuentra por URL, canonicalizándola antes de buscar', () {
      expect(index.find(url: 'https://www.ejemplo.org/'), 'item-url');
    });

    test('el DOI gana sobre el ISBN y la URL', () {
      expect(
        index.find(
          doi: '10.1000/xyz',
          isbn: '9780306406157',
          url: 'https://ejemplo.org',
        ),
        'item-doi',
      );
    });

    test('sin DOI, el ISBN gana sobre la URL', () {
      expect(
        index.find(isbn: '9780306406157', url: 'https://ejemplo.org'),
        'item-isbn',
      );
    });

    test('nada coincide: null', () {
      expect(
        index.find(doi: '10.1000/otro', isbn: '000', url: 'https://otro.org'),
        isNull,
      );
    });

    test('todo nulo: null, sin romper', () {
      expect(index.find(), isNull);
    });
  });
}
