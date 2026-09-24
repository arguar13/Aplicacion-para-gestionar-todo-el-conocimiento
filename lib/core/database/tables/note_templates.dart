import 'package:drift/drift.dart';

/// Una plantilla de nota: su estructura de bloques y sus propiedades, ya
/// puestas, para no armarlas de cero cada vez (F16).
///
/// No es un motor de bloques nuevo: `blocksJson` y `propertiesJson` predefinen
/// bloques y propiedades con los tipos que una nota ya admite hoy —ver
/// `content_block.dart`—, nada más.
@DataClassName('NoteTemplateRow')
class NoteTemplates extends Table {
  @override
  String get tableName => 'note_template';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get blocksJson => text()();
  TextColumn get propertiesJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
