import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/property_value_type.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';

/// Una categoría de propiedad: "Época", "Región", "Tema". La define el
/// usuario, no la app —salvo "Tema" y "Fecha del hecho", categorías de
/// sistema que la propia migración siembra (ver
/// `seed_system_property_categories_v9.dart`).
@DataClassName('PropertyDefinitionRow')
class PropertyDefinitions extends Table {
  TextColumn get id => text()();

  /// Único sin distinguir mayúsculas, mismo criterio que `Tags.name`.
  TextColumn get name => text().unique()();

  DateTimeColumn get createdAt => dateTime()();

  /// Qué clase de valor acepta. `text` para toda categoría creada antes
  /// de que esto existiera, y para cualquiera que se cree sin elegir
  /// otra cosa.
  TextColumn get type =>
      textEnum<PropertyValueType>().withDefault(const Constant('text'))();

  /// `true` para "Tema" y "Fecha del hecho": no se pueden borrar ni
  /// renombrar —ver el guard en
  /// `OrganizeRepositoryImpl.deletePropertyDefinition`—.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

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
@TableIndex(name: 'idx_property_values_parent', columns: {#parentId})
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

  /// Solo si la categoría dueña es de tipo número. [value] sigue siendo
  /// el texto que se muestra.
  RealColumn get numberValue => real().nullable()();

  // Fecha del hecho: año ASTRONÓMICO (1 d.C.=1, 1 a.C.=0, 44 a.C.=-43),
  // firmado, para que ORDER BY cruce el cero sin casos especiales — ver
  // `HistoricalDate` en el dominio. `dateTo*` es un DERIVADO de
  // `dateFrom*`+`datePrecision`, no una segunda fecha que el usuario
  // haya tipeado: viajan las seis juntas, o ninguna (valor no es fecha).
  IntColumn get dateFromYear => integer().nullable()();
  IntColumn get dateFromMonth => integer().nullable()(); // 1-12
  IntColumn get dateFromDay => integer().nullable()(); // 1-31
  IntColumn get dateToYear => integer().nullable()();
  IntColumn get dateToMonth => integer().nullable()();
  IntColumn get dateToDay => integer().nullable()();
  TextColumn get datePrecision => textEnum<DatePrecision>().nullable()();

  /// "circa": el hecho no se sabe con precisión exacta, aunque sí la
  /// precisión nominal ("circa siglo III a.C."). Metadato de
  /// presentación — no afecta el rango.
  BoolColumn get dateIsCirca => boolean().nullable()();

  /// El valor bajo el que está este —«Roma» para «Roma republicana»—, o `null`
  /// si es una raíz (F13). Solo dentro de su misma categoría y solo en las de
  /// texto, sin ciclos: lo hacen cumplir los triggers de
  /// `vocabulary_hierarchy.dart`, no solo el repositorio.
  ///
  /// Si el padre se borra, el hijo pasa a ser raíz; quien borra un padre
  /// —`mergeValues`, `deleteUnusedValues`— sube antes a sus hijos un nivel.
  TextColumn get parentId => text().nullable().references(
    PropertyValues,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Cuántos padres tiene por encima: 0 para una raíz. Está guardado, y no se
  /// calcula al leer, para poder ordenar y filtrar por nivel sin recorrer el
  /// árbol; lo recalcula quien mueve una rama, en la misma transacción, y la
  /// base rechaza pasar de `kVocabularyMaxDepth`.
  IntColumn get depth => integer()
      .withDefault(const Constant(0))
      // La restricción se refiere a la propia columna: es el modo de drift de
      // escribir un `CHECK`, y el analizador lo toma por una recursión.
      // ignore: recursive_getters
      .check(depth.isBetweenValues(0, kVocabularyMaxDepth))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (definition_id, value COLLATE NOCASE)',
  ];
}

/// Un sinónimo que resuelve al mismo valor: "Constantinopla" y "Bizancio"
/// son alias del mismo [PropertyValue].
///
/// [definitionId] está denormalizado desde `PropertyValues.definitionId`
/// —SQLite no puede expresar un `UNIQUE` que cruce a otra tabla vía FK—,
/// para poder exigir que un alias sea único DENTRO DE LA CATEGORÍA, no
/// por valor ni global: "Roma" no puede ser alias de dos valores
/// distintos de "Región" a la vez, pero si además existe una categoría
/// "Ciudad natal", "Roma" ahí es un alias completamente aparte. Que un
/// alias no coincida con el *label* de otro valor de la misma categoría
/// no lo cubre este `UNIQUE` —se valida en código, igual que `renameTag`
/// valida colisiones en Dart—.
@DataClassName('PropertyAliasRow')
@TableIndex(name: 'idx_property_aliases_value', columns: {#propertyValueId})
class PropertyAliases extends Table {
  TextColumn get id => text()();

  TextColumn get propertyValueId =>
      text().references(PropertyValues, #id, onDelete: KeyAction.cascade)();

  TextColumn get definitionId => text().references(
    PropertyDefinitions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get alias => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (definition_id, alias COLLATE NOCASE)',
  ];
}

/// Qué valor de propiedad tiene puesto cada elemento.
///
/// La clave primaria compuesta impide poner el mismo valor dos veces al
/// mismo elemento. A diferencia de `KnowledgeEntries.spaceId` —un elemento
/// pertenece a lo sumo a un espacio—, acá sí hace falta esta
/// tabla de unión: un elemento puede tener varios valores bajo la misma
/// categoría a la vez ("Región: Roma" y "Región: Egipto" en el mismo
/// video).
@DataClassName('ItemPropertyValueRow')
@TableIndex(name: 'idx_item_property_values_value', columns: {#propertyValueId})
class ItemPropertyValues extends Table {
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get propertyValueId =>
      text().references(PropertyValues, #id, onDelete: KeyAction.cascade)();

  /// Cómo llegó a estar puesta: a mano, heredada de la fuente al
  /// extraer una nota, o una sugerencia del modelo ya aceptada. Ver
  /// `ItemPropertyOrigin`.
  TextColumn get origin =>
      textEnum<ItemPropertyOrigin>().withDefault(const Constant('manual'))();

  @override
  Set<Column<Object>> get primaryKey => {itemId, propertyValueId};
}
