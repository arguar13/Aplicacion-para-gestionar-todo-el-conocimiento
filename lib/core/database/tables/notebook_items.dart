import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/notebooks.dart';

/// Qué elementos tiene un cuaderno en modo `manual` (F16, D1).
///
/// Tabla de unión, mismo criterio que `ItemPropertyValues`: un elemento
/// puede estar en varios cuadernos a la vez, y sacarlo de uno no lo borra de
/// la bóveda —solo quita esta fila—.
@DataClassName('NotebookItemRow')
class NotebookItems extends Table {
  @override
  String get tableName => 'notebook_item';

  TextColumn get notebookId =>
      text().references(Notebooks, #id, onDelete: KeyAction.cascade)();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {notebookId, itemId};
}
