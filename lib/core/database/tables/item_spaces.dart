import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/spaces.dart';

/// En qué temas está cada elemento (F37, decisión 80): uno o varios.
///
/// Fue una columna de `item` mientras un elemento estaba en un tema como
/// mucho. Con varios, es una tabla de unión, como `item_property_values`: la
/// clave compuesta impide poner dos veces el mismo tema, y borrar el elemento
/// o el tema se lleva la fila. Ningún tema es el «principal».
///
/// Los temas de un elemento son UN dato para la historia por campo y para la
/// unión de bóvedas (`EntryField.spaces`): gana el último cambio entero, así
/// que un tema que se sacó en un dispositivo no vuelve desde otro.
@DataClassName('ItemSpaceRow')
@TableIndex(name: 'idx_item_spaces_space', columns: {#spaceId})
class ItemSpaces extends Table {
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get spaceId =>
      text().references(Spaces, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {itemId, spaceId};
}
