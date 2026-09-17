import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';

/// Una categoría de propiedad: "Época", "Región", "Tema". La define el
/// usuario, no la app.
@DataClassName('PropertyDefinitionRow')
class PropertyDefinitions extends Table {
  TextColumn get id => text()();

  /// Único sin distinguir mayúsculas, mismo criterio que `Tags.name`.
  TextColumn get name => text().unique()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (name COLLATE NOCASE)'];
}

/// Un valor concreto bajo una categoría: "Roma" bajo "Región". Es su
/// propia fila —y no una columna de texto libre en la tabla de unión— por
/// el mismo motivo que una etiqueta es su propia fila: dos elementos con
/// "Región: Roma" tienen que compartir la misma fila, no dos strings
/// iguales por casualidad, para poder después preguntar "todo lo que
/// tiene esta propiedad puesta" con un solo `join` en vez de comparar
/// texto.
@DataClassName('PropertyValueRow')
@TableIndex(name: 'idx_property_values_definition', columns: {#definitionId})
class PropertyValues extends Table {
  TextColumn get id => text()();

  TextColumn get definitionId => text().references(
    PropertyDefinitions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Único sin distinguir mayúsculas, pero solo dentro de la misma
  /// categoría: "Roma" bajo "Región" y "Roma" bajo cualquier otra
  /// categoría —si alguna vez lo hubiera— no compiten entre sí.
  TextColumn get value => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (definition_id, value COLLATE NOCASE)',
  ];
}

/// Qué valor de propiedad tiene puesto cada elemento.
///
/// La clave primaria compuesta impide poner el mismo valor dos veces al
/// mismo elemento, igual que `ItemTags`. A diferencia de `Items.spaceId`
/// —un elemento pertenece a lo sumo a un espacio—, acá sí hace falta esta
/// tabla de unión: un elemento puede tener varios valores bajo la misma
/// categoría a la vez ("Región: Roma" y "Región: Egipto" en el mismo
/// video).
@DataClassName('ItemPropertyValueRow')
@TableIndex(name: 'idx_item_property_values_value', columns: {#propertyValueId})
class ItemPropertyValues extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get propertyValueId =>
      text().references(PropertyValues, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {itemId, propertyValueId};
}
