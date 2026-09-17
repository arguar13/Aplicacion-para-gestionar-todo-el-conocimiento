import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';

/// Una carpeta del Explorador.
///
/// A diferencia de `Spaces`, esta sí forma un árbol: [parentId] referencia a
/// otra fila de esta misma tabla, `null` para una carpeta de nivel raíz. La
/// cascada es `CASCADE` y no `SET NULL` a propósito — borrar una carpeta
/// borra también sus subcarpetas, igual que borrar una carpeta en un
/// explorador de archivos de verdad se lleva puesto todo lo que tiene
/// adentro. Eso sí, "todo lo que tiene adentro" son las subcarpetas y las
/// filas de `ItemFolders` que las ubicaban ahí, nunca los elementos en sí:
/// esos siguen existiendo en `Items`, solo pierden esa ubicación en
/// particular. Ver el comentario de `Spaces` sobre por qué ese principio —
/// borrar la carpeta no borra el contenido— importa acá también.
@DataClassName('FolderRow')
@TableIndex(name: 'idx_folders_parent', columns: {#parentId})
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// En qué carpetas está cada elemento — puede estar en varias a la vez, a
/// diferencia de los espacios: es lo que permite "copiar" un elemento a otra
/// carpeta sin sacarlo de la primera.
@DataClassName('ItemFolderRow')
@TableIndex(name: 'idx_item_folders_folder', columns: {#folderId})
class ItemFolders extends Table {
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get folderId =>
      text().references(Folders, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {itemId, folderId};
}
