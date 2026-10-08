import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/ai_runs.dart';
import 'package:sinapsis/core/database/tables/chunks.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/flashcard_kind.dart';

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
@TableIndex(name: 'idx_flashcards_ai_run', columns: {#aiRunId})
@TableIndex(name: 'idx_flashcards_group', columns: {#groupId})
class Flashcards extends Table {
  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get front => text()();
  TextColumn get back => text()();

  /// La forma de la tarjeta (F20): `freeRecall` para toda tarjeta que ya
  /// existía —lo que `Flashcard` siempre fue— y para las que se siguen
  /// creando a mano. `multipleChoice`/`trueFalse` son las de un quiz
  /// generado.
  TextColumn get kind =>
      textEnum<FlashcardKind>().withDefault(const Constant('freeRecall'))();

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

  /// Cuándo se exportó por última vez a Anki (F17, D4). Nula hasta la primera
  /// exportación exitosa: una exportación incremental filtra por esto, y
  /// «exportar todo» es la opción aparte que la ignora.
  DateTimeColumn get lastExportedAt => dateTime().nullable()();

  /// Quién la hizo (F27): la persona —todo lo de antes— o la IA. Una de la IA
  /// que la persona edita pasa a ser suya: editarla es adoptarla.
  TextColumn get origin =>
      textEnum<ContentOrigin>().withDefault(const Constant('user'))();

  /// La pasada de la IA que la creó (F27): con ella se deshace entera. `null`
  /// en las de la persona y en las que la persona adoptó.
  TextColumn get aiRunId =>
      text().nullable().references(AiRuns, #id, onDelete: KeyAction.setNull)();

  /// Pausada (F31, v39): no entra en ninguna sesión hasta que se la reactive.
  /// Su calendario no se toca. Falso en todo lo de antes.
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();

  /// Pospuesta (F31, v39): no entra en ninguna sesión mientras `ahora` sea
  /// anterior a esta fecha —el comienzo del próximo día de estudio, que
  /// `StudyDay` calcula—. Se «despospone» sola al llegar; nada la limpia. Nula
  /// en todo lo de antes.
  DateTimeColumn get buriedUntil => dateTime().nullable()();

  /// En qué paso de aprendizaje está (F31, v39): nulo = no se está aprendiendo
  /// ni reaprendiendo (nueva, o ya en repaso por días); 0 = el primer paso
  /// (1 min), 1 = el segundo (10 min). Los pasos de reaprendizaje usan la misma
  /// columna: ver `CardPhase` y `scheduleNext`. Nulo en todo lo de antes.
  IntColumn get learningStep => integer().nullable()();

  /// A qué grupo de tarjetas hermanas pertenece (F31, v39): las dos direcciones
  /// de una pregunta, los huecos de un mismo texto. La cola no muestra dos
  /// hermanas el mismo día. Nulo = sin hermanas, en todo lo de antes.
  TextColumn get groupId => text().nullable()();

  /// Cuál hueco tapa (F31, v39), contando desde 1, en una tarjeta `cloze`. Nulo
  /// en cualquier otra forma.
  IntColumn get clozeIndex => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
