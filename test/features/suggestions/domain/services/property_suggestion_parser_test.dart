import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_parser.dart';

void main() {
  test('interpreta una línea bien formada', () {
    final result = parsePropertySuggestions(
      'PROPIEDAD: Región | Roma',
      knownCategories: ['Región', 'Época'],
    );

    expect(result, [(category: 'Región', value: 'Roma')]);
  });

  test('no distingue mayúsculas y devuelve el nombre canónico de '
      'knownCategories', () {
    final result = parsePropertySuggestions(
      'propiedad: región | Roma',
      knownCategories: ['Región', 'Época'],
    );

    expect(result, [(category: 'Región', value: 'Roma')]);
  });

  test('una categoría que el modelo inventó, fuera de knownCategories, se '
      'descarta', () {
    final result = parsePropertySuggestions(
      'PROPIEDAD: Fecha del hecho | 1492',
      knownCategories: ['Región', 'Época'],
    );

    expect(result, isEmpty);
  });

  test('ignora líneas que no matchean el formato, sin fallar', () {
    final result = parsePropertySuggestions(
      '''
Acá va una explicación libre que el modelo agregó de más.
PROPIEDAD: Región | Roma
Otra línea suelta.
''',
      knownCategories: ['Región'],
    );

    expect(result, hasLength(1));
  });

  test('varias líneas válidas con categorías distintas', () {
    final result = parsePropertySuggestions(
      '''
PROPIEDAD: Región | Roma
PROPIEDAD: Época | Antigüedad
''',
      knownCategories: ['Región', 'Época'],
    );

    expect(result, [
      (category: 'Región', value: 'Roma'),
      (category: 'Época', value: 'Antigüedad'),
    ]);
  });

  test('una respuesta vacía no revienta', () {
    expect(parsePropertySuggestions('', knownCategories: ['Región']), isEmpty);
  });

  test('sin ninguna línea PROPIEDAD, devuelve una lista vacía', () {
    final result = parsePropertySuggestions(
      'No encontré ninguna propiedad aplicable.',
      knownCategories: ['Región'],
    );

    expect(result, isEmpty);
  });

  test('un valor vacío se descarta', () {
    final result = parsePropertySuggestions(
      'PROPIEDAD: Región |',
      knownCategories: ['Región'],
    );

    expect(result, isEmpty);
  });
}
