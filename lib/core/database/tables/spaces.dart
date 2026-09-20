import 'package:drift/drift.dart';

/// Un espacio: una carpeta para agrupar elementos, al estilo de las páginas
/// de nivel superior de Notion.
///
/// Es una tabla aparte y no una columna de texto libre en `item` porque el
/// nombre tiene que poder cambiarse en un solo lugar y reflejarse en todos los
/// elementos que lo usan, y dos espacios con el mismo nombre competirían por
/// agrupar lo mismo. La diferencia con un valor de propiedad es que un
/// elemento pertenece a lo sumo a un espacio —es una carpeta, no una marca—,
/// así que no hace falta una tabla de unión: alcanza con una columna nullable
/// en `item`.
@DataClassName('SpaceRow')
class Spaces extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
