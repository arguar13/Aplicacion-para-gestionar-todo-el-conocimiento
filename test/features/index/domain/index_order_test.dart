import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/index/domain/services/index_order.dart';

/// El orden de la A a la Z del Índice (F46): como lo lee una persona.
void main() {
  test(
    'sin mayúsculas ni acentos: «Ágora» va con la A, no después de la Z',
    () {
      final names = ['Zama', 'ágora', 'Éxodo', 'Bizancio', 'nilo']
        ..sort(compareIndexNames);

      expect(names, ['ágora', 'Bizancio', 'Éxodo', 'nilo', 'Zama']);
    },
  );

  test('la ñ es una letra propia, después de la n, como en el diccionario', () {
    final names = ['oasis', 'Ñandú', 'nilo', 'nz', 'Nápoles']
      ..sort(compareIndexNames);

    expect(names, ['Nápoles', 'nilo', 'nz', 'Ñandú', 'oasis']);
  });

  test('lo que no es letra ni número queda, y separa palabras', () {
    expect(indexSortKey('  El Concilio de Nicea  '), 'el concilio de nicea');
    expect(indexSortKey('Roma: la República'), 'roma: la republica');
  });

  test('iguales así, por cómo están escritos: el orden no depende de cómo '
      'llegaron', () {
    expect(compareIndexNames('Roma', 'roma'), lessThan(0));
    expect(compareIndexNames('roma', 'Roma'), greaterThan(0));
    expect(compareIndexNames('Roma', 'Roma'), 0);
  });
}
