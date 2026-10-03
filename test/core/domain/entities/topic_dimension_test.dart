import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';

/// Por qué agrupan el Mapa y el Atlas (F28): qué se ofrece y qué se muestra
/// por defecto.
void main() {
  final created = DateTime(2026, 10, 3);
  final epoca = PropertyDefinition(
    id: 'epoca',
    name: 'Época',
    createdAt: created,
  );
  final tema = PropertyDefinition(
    id: 'tema',
    name: kTemaCategoryName,
    createdAt: created,
    isSystem: true,
  );
  final autor = PropertyDefinition(
    id: 'autor',
    name: kAutorCategoryName,
    createdAt: created,
    type: PropertyValueType.person,
    isSystem: true,
  );

  test('ofrece los temas, las etiquetas y las demás categorías de texto, en '
      'ese orden', () {
    final (:options, selected: _) = topicDimensionsOf([
      epoca,
      autor,
      tema,
    ], hasSpaces: false);

    expect(
      [for (final o in options) o.id],
      [kSpacesDimensionId, 'tema', 'epoca'],
    );
    expect(options.first.isSpaces, isTrue);
    expect(options[1].isTags, isTrue);
  });

  test('con temas, muestra los temas', () {
    final (options: _, :selected) = topicDimensionsOf([tema], hasSpaces: true);

    expect(selected.isSpaces, isTrue);
  });

  test('sin temas, muestra las etiquetas', () {
    final (options: _, :selected) = topicDimensionsOf([
      epoca,
      tema,
    ], hasSpaces: false);

    expect(selected.isTags, isTrue);
  });

  test('lo elegido manda, también los temas sin ninguno', () {
    expect(
      topicDimensionsOf(
        [tema, epoca],
        hasSpaces: true,
        chosenId: 'epoca',
      ).selected.id,
      'epoca',
    );
    expect(
      topicDimensionsOf(
        [tema],
        hasSpaces: false,
        chosenId: kSpacesDimensionId,
      ).selected.isSpaces,
      isTrue,
    );
  });

  test('una elegida que ya no existe vuelve a la de por defecto', () {
    final (options: _, :selected) = topicDimensionsOf(
      [tema],
      hasSpaces: false,
      chosenId: 'borrada',
    );

    expect(selected.isTags, isTrue);
  });

  test('el identificador de los temas no es el de ninguna categoría', () {
    expect(isSpacesDimension(kSpacesDimensionId), isTrue);
    expect(isSpacesDimension('tema'), isFalse);
  });
}
