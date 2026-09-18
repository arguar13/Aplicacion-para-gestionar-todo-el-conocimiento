import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

/// La extensión de [KnowledgeEntries] para lo que el usuario construye:
/// sin procedencia propia, mutable, con un subtipo y una madurez.
@DataClassName('KnowledgeNoteRow')
class KnowledgeNotes extends Table {
  @override
  String get tableName => 'note';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get noteKind => textEnum<NoteKind>()();
  TextColumn get maturity => textEnum<NoteMaturity>()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
