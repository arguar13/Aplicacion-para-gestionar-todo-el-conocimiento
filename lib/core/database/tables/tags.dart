import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';

/// Las etiquetas.
///
/// OBSOLETA desde F8: una etiqueta es ahora un valor de la categoría de
/// sistema "Tema" (`PropertyValues`), y la app ya no lee ni escribe esta
/// tabla. Se conserva, con sus filas, hasta que F10 retire el modelo viejo: la
/// migración v14 —retirada con los pasos anteriores a v15— ya unió lo que tenía
/// con Tema. No agregar código nuevo que la use.
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
/// OBSOLETA desde F8, igual que [Tags]: las etiquetas de un elemento son
/// sus asignaciones de valores de Tema en `ItemPropertyValues`. La retira
/// F10.
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
