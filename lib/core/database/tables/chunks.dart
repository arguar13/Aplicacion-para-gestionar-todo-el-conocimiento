import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';

/// Un fragmento del texto íntegro de una fuente —indexado, no reducción—.
///
/// Concatenar [content] de todos los chunks de un `itemId`, en orden de
/// [seq], reproduce `KnowledgeSources.fullText` carácter a carácter. Ver
/// `ChunkingService`/`chunkingInvariantHolds` en
/// `lib/core/domain/services/chunking_service.dart`.
@DataClassName('ChunkRow')
@TableIndex(name: 'idx_chunks_item_seq', columns: {#itemId, #seq})
@TableIndex(name: 'idx_chunks_item_start_ms', columns: {#itemId, #startMs})
class Chunks extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get seq => integer()();
  TextColumn get content => text()();
  IntColumn get charStart => integer()();
  IntColumn get charEnd => integer()();
  IntColumn get startMs => integer().nullable()();
  IntColumn get endMs => integer().nullable()();
  IntColumn get pageNumber => integer().nullable()();
  TextColumn get headingPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (item_id, seq)'];
}
