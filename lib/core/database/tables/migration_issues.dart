import 'package:drift/drift.dart';

/// Una fila que no pudo migrarse limpiamente a un esquema nuevo.
///
/// No la pide el encargo de forma explícita, pero hace falta para cumplir
/// su propio criterio de aceptación: si algo no reconstruye exacto, se
/// aborta esa fila puntual y se reporta, sin pisarla ni abortar el resto
/// de la migración.
@DataClassName('MigrationIssueRow')
class MigrationIssues extends Table {
  TextColumn get id => text()();

  /// Qué migración la generó, ej. `'f1_knowledge_model'`.
  TextColumn get migration => text()();

  /// El id del elemento afectado, en el esquema de origen. Sin FK a
  /// propósito: puede referir a una fila que, por el motivo mismo del
  /// problema, no llegó a tener su contraparte en el esquema nuevo.
  TextColumn get itemId => text()();

  /// En qué paso de la migración pasó: `'classify'`, `'chunk'`, ...
  TextColumn get stage => text()();
  TextColumn get message => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
