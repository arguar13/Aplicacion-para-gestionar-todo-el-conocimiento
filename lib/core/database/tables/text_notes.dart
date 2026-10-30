import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/study_creations.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';

/// Una nota en el texto (F45, mejora 19, decisión I, v49): lo que la persona
/// escribe sobre un pedazo de un texto, como una nota de Adobe Reader o un
/// comentario de Word. Una tabla para todos los textos, para que se vean y se
/// comporten igual en todos lados.
///
/// - **De qué texto es** ([target], `TextNoteTarget.storageKey`), cada uno por
///   su clave (decisión H): nada de uno aparece en otro.
///   - `source_original`: el original de una fuente de la Biblioteca. Es de la
///     fuente ([itemId]) y está escrita sobre su texto extraído
///     ([renditionId]);
///   - `processed_original`: la copia del original de un documento procesado
///     ([itemId] es el documento). Sus posiciones son del texto de la fuente
///     con que se corresponde la copia, como lo elegido del procesado;
///   - `processed_text`: el texto propio de un documento procesado —sus
///     páginas de «Texto», o el de su fuente si no las tiene—, y lo que se lee
///     de él: el resumen y la síntesis son sus oraciones, en sus posiciones;
///   - `creation`: lo creado en Repasar ([creationId]).
/// - **Su lugar** es el tramo `[startOffset, endOffset)` de ese texto, y el
///   pedazo citado ([excerpt]) va copiado: si el texto se vuelve a extraer, la
///   nota se reubica por él (`TextAnchorRelocator`), como un subrayado. Si ya
///   no se encuentra, queda **sin lugar** —las dos posiciones en `null`— y
///   conserva lo demás: una nota no se pierde nunca.
/// - **[renditionId] va sin clave foránea, a propósito.** Soltar el texto de
///   una fuente a la papelera del contenido —o que se vaya de verdad— no se
///   lleva las notas ni las deja colgando de nada: la nota es de la fuente, y
///   el texto que falta solo la deja sin lugar. Si el texto vuelve, con su id,
///   la nota vuelve a su lugar.
/// - **Se va con lo suyo**: con la fuente o el documento procesado cuando se
///   borran de verdad (vaciando la papelera), y con la creación. Borrar una
///   nota no toca nunca el documento (decisión E): de la Biblioteca nada se
///   borra, las notas se agregan.
/// - Se busca por su propio índice de texto (`text_note_search`), que también
///   lleva las notas de los resaltados de antes (F38): ver
///   `createTextNoteSearchTable`.
///
/// Viaja en la copia de la bóveda (la base entera) y en la unión, donde queda
/// la versión editada más tarde.
@DataClassName('TextNoteRow')
//
// Las notas de un texto se leen por su dueño —la fuente, el documento o la
// creación— y su clase; las de una forma, al reubicarlas.
@TableIndex(name: 'idx_text_notes_item', columns: {#itemId, #target})
@TableIndex(name: 'idx_text_notes_creation', columns: {#creationId})
@TableIndex(name: 'idx_text_notes_rendition', columns: {#renditionId})
class TextNotes extends Table {
  @override
  String get tableName => 'text_notes';

  /// La clave entera que usa el índice de texto para volver a la fila: ver
  /// `Chunks.rowKey` para por qué no puede ser el `rowid` implícito.
  IntColumn get rowKey => integer().autoIncrement()();

  /// La identidad de siempre, estable: la que ven el resto de la app y la
  /// unión de bóvedas.
  TextColumn get id => text().unique()();

  /// De qué texto es: `TextNoteTarget.storageKey`.
  TextColumn get target => text()();

  /// La fuente o el documento procesado de la nota; `null` en una creación.
  TextColumn get itemId => text().nullable().references(
    KnowledgeEntries,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// La forma de texto de la fuente sobre la que se escribió, en el original
  /// de la Biblioteca; `null` en los demás. Sin clave foránea: ver arriba.
  TextColumn get renditionId => text().nullable()();

  /// La creación de la nota; `null` en las demás.
  TextColumn get creationId => text().nullable().references(
    StudyCreations,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Su lugar en el texto, `[startOffset, endOffset)`; los dos en `null` si
  /// quedó sin lugar.
  IntColumn get startOffset => integer().nullable()();
  IntColumn get endOffset => integer().nullable()();

  /// El pedazo citado, copiado: con él se reubica.
  TextColumn get excerpt => text()();

  /// Lo que la persona escribió.
  TextColumn get note => text()();

  /// Uno de los colores de resaltar (F38), por nombre.
  TextColumn get color => textEnum<HighlightColor>()();

  DateTimeColumn get createdAt => dateTime()();

  /// Cuándo la persona la editó por última vez: la escritura o el color.
  /// Reubicarla no la cambia —no es una edición—, y es lo que decide qué
  /// versión queda en la unión de bóvedas.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    // Una sola línea a propósito: drift solo lee el texto de una restricción
    // si es un literal entero (ver `ProcessedParts`).
    // ignore: lines_longer_than_80_chars
    "CHECK (target IN ('source_original', 'processed_original', 'processed_text', 'creation'))",
    // Cada clase, con su dueño y nada más.
    "CHECK ((creation_id IS NOT NULL) = (target = 'creation'))",
    "CHECK ((item_id IS NOT NULL) = (target <> 'creation'))",
    "CHECK ((rendition_id IS NOT NULL) = (target = 'source_original'))",
    'CHECK ((start_offset IS NULL) = (end_offset IS NULL))',
    'CHECK (start_offset IS NULL OR start_offset >= 0)',
    'CHECK (start_offset IS NULL OR end_offset > start_offset)',
    'CHECK (length(excerpt) > 0)',
    'CHECK (length(trim(note)) > 0)',
  ];
}
