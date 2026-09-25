import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/flashcards.dart';

/// Una opción de una tarjeta de opción múltiple (F20): su texto, si es la
/// correcta, y su propia procedencia.
///
/// Solo para `FlashcardKind.multipleChoice` —verdadero/falso usa la
/// procedencia que `Flashcard` ya tiene, sin esta tabla—. Cada opción ancla
/// a su propio chunk en vez de usar `relations`/`extractedFrom`: esa tabla
/// tiene `UNIQUE(from_item_id, to_item_id, kind)`, y dos opciones de la
/// MISMA pregunta —la correcta y un distractor, o dos distractores— citando
/// el mismo elemento fuente es esperable, no un caso raro. Mismo patrón que
/// `Flashcard.sourceChunkId/sourceCharStart/sourceCharEnd` ya usa para una
/// tarjeta común.
@DataClassName('FlashcardOptionRow')
@TableIndex(name: 'idx_flashcard_options_flashcard', columns: {#flashcardId})
class FlashcardOptions extends Table {
  TextColumn get id => text()();

  TextColumn get flashcardId =>
      text().references(Flashcards, #id, onDelete: KeyAction.cascade)();

  TextColumn get content => text()();

  BoolColumn get isCorrect => boolean()();

  /// El orden en el que la opción se muestra. Sin esto, el orden de lectura
  /// de la tabla no tiene por qué coincidir con el que el usuario vio al
  /// revisar la pregunta.
  IntColumn get position => integer()();

  /// Igual que `Flashcard.sourceChunkId`: nulo si el texto de la fuente se
  /// rehizo y sus chunks se reemplazaron. El rango de caracteres sigue
  /// valiendo mientras el texto no cambie.
  TextColumn get sourceChunkId =>
      text().nullable().references(Chunks, #id, onDelete: KeyAction.setNull)();
  IntColumn get sourceCharStart => integer().nullable()();
  IntColumn get sourceCharEnd => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
