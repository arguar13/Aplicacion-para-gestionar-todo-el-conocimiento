import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/properties.dart';

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

/// Los vectores de una nota (F27, v35): lo que la hace candidata a un vínculo
/// de la IA igual que una fuente.
///
/// Una fuente tiene sus vectores por fragmento (`chunks` + [Embeddings]); una
/// nota no se fragmenta —es texto de la persona, que cambia, y su búsqueda la
/// hace `item_search`—, así que sus vectores van acá: uno por tramo del texto
/// (`splitIntoParts`, de `kNoteEmbeddingPieceChars`), en orden ([seq]).
///
/// [textHash] dice qué texto describen: si la nota cambió, los tramos de otro
/// texto se descartan y se calculan de nuevo. Se calculan por tandas y cada
/// tanda queda guardada, como los de las fuentes: lo que se cortó a mitad se
/// retoma desde lo que falta.
///
/// Derivados, como [Embeddings]: no viajan en la fusión de bóvedas —se
/// recalculan— y se van con su nota.
@DataClassName('NoteEmbeddingRow')
class NoteEmbeddings extends Table {
  @override
  String get tableName => 'note_embedding';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// El lugar del tramo en la nota, desde 0.
  IntColumn get seq => integer()();
  BlobColumn get vector => blob()();

  /// El SHA-256 del texto entero de la nota que estos tramos describen.
  TextColumn get textHash => text()();
  TextColumn get modelVersion => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, seq};
}

/// El vector de un valor del vocabulario (F27, v35): con qué se elige qué
/// parte del vocabulario ve el modelo cuando pone las propiedades de un
/// elemento (`selectVocabularyForPrompt`). Un vocabulario de miles de valores
/// no entra en la ventana del modelo; los más cercanos al texto, sí.
///
/// [label] es el texto que describe: si el valor se renombra, se calcula de
/// nuevo. Derivado, como [Embeddings]: no viaja en la fusión y se va con su
/// valor.
@DataClassName('PropertyValueEmbeddingRow')
class PropertyValueEmbeddings extends Table {
  @override
  String get tableName => 'property_value_embedding';

  TextColumn get valueId =>
      text().references(PropertyValues, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text()();
  BlobColumn get vector => blob()();
  TextColumn get modelVersion => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {valueId};
}
