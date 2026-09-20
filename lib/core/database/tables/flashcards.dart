import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';

/// Una tarjeta de repaso: una pregunta, una respuesta, y el estado de
/// repetición espaciada que decide cuándo volver a mostrarla.
///
/// Cuelga de un elemento (`item`, `CASCADE`) y no de una rendition: a
/// diferencia de un resaltado —que marca un fragmento concreto de un texto
/// concreto—, una tarjeta es una síntesis de lo que el elemento enseña, y
/// eso no cambia si la transcripción se rehace con un modelo mejor.
@DataClassName('FlashcardRow')
@TableIndex(name: 'idx_flashcards_item', columns: {#itemId})
@TableIndex(name: 'idx_flashcards_due_at', columns: {#dueAt})
class Flashcards extends Table {
  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get front => text()();
  TextColumn get back => text()();

  /// El factor de facilidad de SM-2 (Anki usa el mismo algoritmo, con estas
  /// mismas variables). Arranca en 2.5 —el valor de origen del algoritmo— y
  /// sube o baja según qué tan fácil resultó cada repaso: nunca por debajo
  /// de 1.3, el piso que el propio SM-2 define para que una tarjeta muy
  /// difícil no termine con un intervalo que se reduce a casi nada.
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();

  /// Cuántos días hasta el próximo repaso, la última vez que se calculó.
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();

  /// Cuántas veces seguidas se contestó bien. Se reinicia a 0 apenas se
  /// contesta "de nuevo": es lo que hace que SM-2 vuelva a tratarla como una
  /// tarjeta nueva en vez de seguir alargando un intervalo que ya demostró
  /// no funcionar.
  IntColumn get repetitions => integer().withDefault(const Constant(0))();

  /// Cuándo toca repasarla. Ya es responsabilidad de acá y no de calcularlo
  /// cada vez en el momento de listar: `dueAt <= ahora` es el filtro entero
  /// de "qué repasar hoy", indexado.
  DateTimeColumn get dueAt => dateTime()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();

  /// El fragmento de la fuente del que salió la tarjeta (F11), si se sabe.
  ///
  /// Si el texto de la fuente se rehace, sus chunks se reemplazan y esta
  /// referencia queda en nulo: por eso la tarjeta guarda además el rango de
  /// caracteres, que es lo que usa el lector para saltar al lugar —y que sigue
  /// valiendo mientras el texto no cambie—.
  TextColumn get sourceChunkId =>
      text().nullable().references(Chunks, #id, onDelete: KeyAction.setNull)();

  /// Dónde, en el texto de la forma principal del elemento, está el fragmento
  /// del que salió. Los mismos desplazamientos que usan `Chunks` y `Relations`.
  IntColumn get sourceCharStart => integer().nullable()();
  IntColumn get sourceCharEnd => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
