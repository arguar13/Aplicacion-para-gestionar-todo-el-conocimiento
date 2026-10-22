import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/entry_fields.dart';

/// Los temas de un elemento como texto (F37): lo que guarda un conflicto de
/// fusión y lo que lee quien lo resuelve.
void main() {
  group('encodeSpaceIds', () {
    test('en orden, para que el mismo conjunto sea siempre el mismo texto', () {
      expect(encodeSpaceIds({'h', 'f', 'a'}), '["a","f","h"]');
      expect(encodeSpaceIds({'a', 'h', 'f'}), encodeSpaceIds({'h', 'f', 'a'}));
    });

    test('sin ninguno es «nada», como un campo vacío', () {
      expect(encodeSpaceIds(const {}), isNull);
    });
  });

  group('decodeSpaceIds', () {
    test('vuelve al conjunto que se guardó', () {
      expect(decodeSpaceIds(encodeSpaceIds({'h', 'f'})), {'h', 'f'});
    });

    test('«nada» es sin tema', () {
      expect(decodeSpaceIds(null), isEmpty);
      expect(decodeSpaceIds(''), isEmpty);
    });

    test('un conflicto de antes de F37 guardaba un tema solo: es ese', () {
      expect(decodeSpaceIds('sp-historia'), {'sp-historia'});
    });

    test('un texto que no es una lista de temas no es un conjunto', () {
      expect(decodeSpaceIds('[1, 2]'), isNull);
      expect(decodeSpaceIds('["a", 3]'), isNull);
      expect(decodeSpaceIds('[roto'), isNull);
    });
  });
}
