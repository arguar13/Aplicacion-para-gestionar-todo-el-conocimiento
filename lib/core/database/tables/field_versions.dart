import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';

/// Quién cambió cada campo de un elemento por última vez, y cuándo (F11).
///
/// Es la precondición de una fusión que no destruye: dos bóvedas que cambiaron
/// el MISMO campo del MISMO elemento solo se pueden combinar sin pisar nada si
/// cada una sabe quién lo tocó y sobre qué versión. No sincroniza nada por sí
/// sola.
///
/// Una fila por (elemento, campo). El nombre del campo es el de la columna
/// (`title`, `subtitle`, `notes`, `spaceId`, `state`, `deletedAt`, `noteKind`,
/// `maturity`, los metadatos de la fuente) o `rendition:<id>` para el texto de
/// una forma.
///
/// **Linaje.** [updatedAt]/[deviceId] son la última edición. [baseUpdatedAt] y
/// [baseDeviceId] son la versión AJENA sobre la que se editó, o nulos si la
/// cadena de ediciones es propia. Con eso se distingue «edité encima de la
/// versión que recibí» —no es conflicto— de «los dos editamos a la vez» —sí lo
/// es—: sin ellos, en el uso normal —teléfono, compu, teléfono— casi todo se
/// marcaría como conflicto. Ver `KnowledgeEntryWriter`.
///
/// [deviceId] es `legacy` en lo escrito antes de F11, cuando el identificador
/// de dispositivo era un texto fijo.
@DataClassName('FieldVersionRow')
class FieldVersions extends Table {
  @override
  String get tableName => 'field_version';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get fieldName => text()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get deviceId => text()();

  DateTimeColumn get baseUpdatedAt => dateTime().nullable()();

  TextColumn get baseDeviceId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, fieldName};
}
