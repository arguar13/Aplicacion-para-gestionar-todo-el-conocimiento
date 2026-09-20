import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';

/// Un fragmento del texto íntegro de una fuente —indexado, no reducción—.
///
/// Concatenar [content] de todos los chunks de un `itemId`, en orden de
/// [seq], reproduce el texto de la forma principal del elemento carácter a
/// carácter. Ver `ChunkingService`/`chunkingInvariantHolds` en
/// `lib/core/domain/services/chunking_service.dart`.
@DataClassName('ChunkRow')
@TableIndex(name: 'idx_chunks_item_seq', columns: {#itemId, #seq})
@TableIndex(name: 'idx_chunks_item_start_ms', columns: {#itemId, #startMs})
class Chunks extends Table {
  /// La clave de la fila: un entero que SQLite numera y que el índice de texto
  /// (`chunk_search`, FTS5 de contenido externo) usa para volver a la fila.
  ///
  /// Hace falta aparte de [id] por el `rowid` implícito: una tabla con clave
  /// primaria de texto tiene uno, pero SQLite puede renumerarlo en un `VACUUM`
  /// —y `VACUUM INTO`, que usan los respaldos, es un `VACUUM`—, y el índice
  /// quedaría apuntando a filas equivocadas sin que nada lo avise. Un entero
  /// declarado como clave primaria es el propio rowid y nunca se renumera.
  IntColumn get rowKey => integer().autoIncrement()();

  /// La identidad de siempre: la que referencian los embeddings y la que ven
  /// el resto de la app. Única, para que las claves foráneas puedan apuntarle.
  TextColumn get id => text().unique()();
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
  List<String> get customConstraints => ['UNIQUE (item_id, seq)'];
}
