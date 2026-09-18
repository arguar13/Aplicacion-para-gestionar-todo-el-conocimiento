import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';

/// La extensión de [KnowledgeEntries] para lo que el usuario construye:
/// sin procedencia propia, mutable, con un subtipo y una madurez.
@DataClassName('KnowledgeNoteRow')
@TableIndex(name: 'idx_knowledge_notes_dedup_hash', columns: {#dedupHash})
class KnowledgeNotes extends Table {
  @override
  String get tableName => 'note';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get noteKind => textEnum<NoteKind>()();
  TextColumn get maturity => textEnum<NoteMaturity>()();

  /// SHA-256 del contenido normalizado (minúsculas, sin puntuación,
  /// espacios colapsados) — F7, deduplicación. A diferencia de
  /// `KnowledgeSources`, acá no hay ningún `fullText`/`contentHash`
  /// previo que preservar: una nota es mutable, así que este valor se
  /// recalcula en cada guardado, sin guarda de idempotencia — ver
  /// `LibraryRepositoryImpl.save()`.
  TextColumn get dedupHash => text().nullable()();

  /// Huella de 64 bits para casi-duplicados — F7, deduplicación. Ver
  /// `DedupFingerprint`.
  TextColumn get simhash => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};
}
