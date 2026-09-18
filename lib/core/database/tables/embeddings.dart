import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';

/// El vector de un chunk, para similitud semántica.
///
/// Solo esquema en F1: ninguna fila se escribe ni se lee todavía. Se crea
/// ahora porque su forma ya está completamente especificada y no cuesta
/// una migración aparte más adelante — ver la decisión sobre similitud
/// semántica en docs/arquitectura.md.
@DataClassName('EmbeddingRow')
class Embeddings extends Table {
  TextColumn get chunkId =>
      text().references(Chunks, #id, onDelete: KeyAction.cascade)();
  BlobColumn get vector => blob()();
  TextColumn get modelVersion => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {chunkId};
}
