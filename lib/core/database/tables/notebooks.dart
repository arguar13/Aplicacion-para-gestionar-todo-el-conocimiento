import 'package:drift/drift.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';

/// Un cuaderno: un subconjunto con nombre de la bóveda, para acotar el chat
/// o para agrupar sin exigir que cada elemento viva en un solo lugar —a
/// diferencia de `Space` (F16, D1).
///
/// `queryJson` solo tiene algo en modo `query`; en modo `manual` la
/// pertenencia vive en `notebook_item`, no acá.
@DataClassName('NotebookRow')
class Notebooks extends Table {
  @override
  String get tableName => 'notebook';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get mode => textEnum<NotebookMode>()();
  TextColumn get queryJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
