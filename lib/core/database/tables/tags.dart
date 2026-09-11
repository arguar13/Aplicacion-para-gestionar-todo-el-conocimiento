import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';

/// Las etiquetas.
@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();

  /// Único sin distinguir mayúsculas (ver `COLLATE NOCASE`): "Filosofía" y
  /// "filosofía" tienen que ser la misma etiqueta. Dejar que convivan parte la
  /// biblioteca en dos mitades que no se encuentran entre sí, y el usuario
  /// nunca se entera de por qué le faltan cosas.
  TextColumn get name => text().unique()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (name COLLATE NOCASE)'];
}

/// Qué etiqueta tiene qué elemento.
///
/// La clave primaria compuesta impide poner dos veces la misma etiqueta al
/// mismo elemento, sin necesidad de comprobarlo en el código.
@DataClassName('ItemTagRow')
@TableIndex(name: 'idx_item_tags_tag', columns: {#tagId})
class ItemTags extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {itemId, tagId};
}
