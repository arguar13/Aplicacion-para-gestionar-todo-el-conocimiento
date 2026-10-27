import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// Un documento procesado (F41, v45, decisión A): la información pura que la
/// persona sacó de UNA fuente de la Biblioteca al triarla.
///
/// Es un elemento de la bóveda como cualquier otro —una fila de `item` con su
/// `note` de tipo `NoteKind.processed`—, así que viaja en la papelera, la copia
/// y la unión de bóvedas. Esta tabla le agrega lo que lo hace un procesado: de
/// qué fuente salió. Su contenido son sus partes ([ProcessedParts]); no tiene
/// formas (`renditions`) propias.
///
/// - **Uno por fuente**, y lo garantiza la base: [sourceItemId] es único. Su
///   id, además, sale de la fuente (`processedDocumentIdFor`): dos dispositivos
///   que procesan la misma fuente cada uno por su cuenta llegan al MISMO
///   elemento, y la unión de bóvedas lo junta en vez de chocar.
/// - **De la Biblioteca nada se borra**: procesar nunca toca la fuente. Si
///   alguien la borra de verdad —vaciando la papelera—, el procesado queda,
///   con su texto, y su enlace pasa a `null` («el original ya no está»): es una
///   copia propia, no un reflejo.
@DataClassName('ProcessedDocumentRow')
class ProcessedDocuments extends Table {
  @override
  String get tableName => 'processed_documents';

  /// El elemento del procesado: su título, su papelera, sus temas.
  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// La fuente de la que salió, para «Ver el original en la Biblioteca».
  /// Única: un procesado por fuente. `null` solo si la fuente se borró de
  /// verdad.
  TextColumn get sourceItemId => text().nullable().unique().references(
    KnowledgeEntries,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// De qué tipo era la fuente al procesarla —un libro, un video, una página—:
  /// el ícono de la fila y el filtro «tipo de fuente» de Procesado. Se guarda
  /// y no se lee de la fuente para que siga valiendo si la fuente se va.
  TextColumn get sourceKind => textEnum<SourceKind>()();

  DateTimeColumn get createdAt => dateTime()();

  /// Hasta dónde se estudió SU propio texto (decisión I, v46): la posición del
  /// texto que se estudia (`ProcessedStudyText`) hasta la que llegó el
  /// análisis, como `study_analyses.analyzed_until`. Vuelve a 0 cuando ese
  /// texto cambia —se edita, se reemplaza o se quita una página—: las
  /// posiciones ya no son las mismas.
  IntColumn get studyAnalyzedUntil =>
      integer().withDefault(const Constant(0))();

  /// Cuándo terminó de estudiarse su texto; `null` si falta.
  DateTimeColumn get studyCompletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {itemId};

  @override
  List<String> get customConstraints => [
    // Una fuente no se procesa a sí misma.
    'CHECK (source_item_id IS NULL OR source_item_id <> item_id)',
  ];
}

/// La copia del original de un documento procesado (F41, v46, decisión H):
/// el PDF, el Word, el EPUB, el texto o la página web archivada de su fuente,
/// copiado como un archivo propio.
///
/// El archivo es una forma (`renditions`) del procesado —con su ruta, su tipo y
/// su peso—, así que viaja como cualquier archivo de la bóveda: lo cuentan
/// `isFileReferenced`, la copia de la bóveda (vive en `originales/`), la unión
/// (`OriginalFilesMerge` copia lo que referencia una forma) y el borrado de
/// verdad. Esta fila le agrega lo que lo hace la copia de un original:
///
/// - de qué archivo de la fuente salió y cuánto pesaba ([sourceFilePath],
///   [sourceFileSize]): «Actualizar» vuelve a copiar solo si cambió. Un
///   original de la Biblioteca se escribe una vez y no se reescribe: otro
///   archivo es otra ruta;
/// - con qué texto de la fuente se corresponde ([textHash], el
///   `source.content_hash` de ese momento): las marcas de lo elegido se pintan
///   sobre la copia solo mientras el texto de la fuente siga siendo ese. Si no,
///   no se pinta nada —mejor nada que marcas corridas—.
///
/// Su id de forma sale del documento (`processedOriginalRenditionIdFor`): dos
/// dispositivos que copian el original del mismo procesado llegan a la misma
/// forma. Se va con su forma; soltar el archivo de la fuente no la toca, y al
/// revés.
@DataClassName('ProcessedOriginalRow')
class ProcessedOriginals extends Table {
  @override
  String get tableName => 'processed_originals';

  TextColumn get documentId => text().references(
    ProcessedDocuments,
    #itemId,
    onDelete: KeyAction.cascade,
  )();

  /// La forma del procesado con el archivo copiado.
  TextColumn get renditionId => text().unique().references(
    Renditions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// El archivo de la fuente que se copió, y cuánto pesaba.
  TextColumn get sourceFilePath => text()();
  IntColumn get sourceFileSize => integer()();

  /// El `content_hash` de la fuente cuando se copió; `null` si todavía no
  /// tenía texto.
  TextColumn get textHash => text().nullable()();

  DateTimeColumn get copiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};

  @override
  List<String> get customConstraints => ['CHECK (source_file_size >= 0)'];
}

/// Una parte de un documento procesado (F41, v45, decisión B): una página del
/// texto, una oración del resumen, de la síntesis o con palabras clave (v46),
/// una nota o un fragmento.
///
/// Cada una sabe de dónde salió ([origin], [edited]) y dónde estaba en el
/// original ([sourceRenditionId], [sourceStart], [sourceEnd]: posiciones del
/// texto entero de la fuente, como `study_marks` y `dated_events`). Eso es lo
/// que permite «Abrir en el original» justo en su lugar y elegir, al volver a
/// triar, entre agregar, actualizar, reemplazar y quitar sin adivinar.
///
/// - **El ancla vale mientras la forma exista.** Si la forma de la fuente se va
///   —se soltó a la papelera del contenido, o la fuente se borró de verdad—, la
///   parte se queda con su texto y [sourceRenditionId] pasa a `null`; las
///   posiciones quedan como estaban, para que recuperar el texto devuelva el
///   ancla (`content_trash.processed_parts`). Una parte copiada siempre sabe
///   DÓNDE estaba, aunque ya no pueda abrirse.
/// - **El texto de la sección «Texto» se guarda por páginas**
///   (`kProcessedTextPageChars`): concatenadas en orden reproducen el texto
///   copiado carácter por carácter. Corregir una página reescribe esa página, y
///   la búsqueda reindexa esa página: nada cuesta lo que mide el libro.
/// - Se busca por su propio índice de texto (`processed_part_search`, FTS5 de
///   contenido externo por [rowKey], como `chunk_search`).
@DataClassName('ProcessedPartRow')
@TableIndex(
  name: 'idx_processed_parts_document',
  columns: {#documentId, #section, #position},
)
@TableIndex(
  name: 'idx_processed_parts_rendition',
  columns: {#sourceRenditionId},
)
class ProcessedParts extends Table {
  @override
  String get tableName => 'processed_parts';

  /// La clave entera que usa el índice de texto para volver a la fila: ver
  /// `Chunks.rowKey` para por qué no puede ser el `rowid` implícito.
  IntColumn get rowKey => integer().autoIncrement()();

  /// La identidad de siempre, estable: la que ven el resto de la app y la
  /// unión de bóvedas.
  TextColumn get id => text().unique()();

  TextColumn get documentId => text().references(
    ProcessedDocuments,
    #itemId,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get section => textEnum<ProcessedSection>()();

  /// El orden dentro de su sección, de 0 en adelante.
  IntColumn get position => integer()();

  /// El texto de la parte, tal como se lee hoy.
  TextColumn get content => text()();

  TextColumn get origin => textEnum<ProcessedPartOrigin>()();

  /// Si la persona editó una parte copiada: «Actualizar» ya no la pisa. Siempre
  /// en falso en una escrita por la persona.
  BoolColumn get edited => boolean().withDefault(const Constant(false))();

  /// La forma de texto de la fuente de la que salió. `null` si se fue, o si es
  /// una nota que no salió de ningún pasaje.
  TextColumn get sourceRenditionId => text().nullable().references(
    Renditions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Dónde estaba en el texto de la fuente: `[sourceStart, sourceEnd)`. Las dos
  /// juntas o ninguna.
  IntColumn get sourceStart => integer().nullable()();
  IntColumn get sourceEnd => integer().nullable()();

  /// Dónde está en el texto PROPIO del procesado (decisión I, v46): el tramo
  /// `[textStart, textEnd)` de su sección «Texto» —sus páginas, una detrás de
  /// la otra—. Una página lo lleva siempre: es su lugar en ese texto. Una
  /// oración lo lleva mientras se sepa dónde está: lo estudiado en el
  /// procesado siempre, y lo copiado de la fuente mientras su página sea
  /// todavía la de la fuente. Corregir una página corre lo que le sigue.
  IntColumn get textStart => integer().nullable()();
  IntColumn get textEnd => integer().nullable()();

  /// En una parte de las palabras clave, los tramos de cada palabra dentro de
  /// [content], en JSON (`encodeProcessedSpans`): `[[inicio, fin], …]`, en
  /// orden. Nulo en las demás secciones.
  TextColumn get spans => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (length(content) > 0)',
    'CHECK (position >= 0)',
    'CHECK ((source_start IS NULL) = (source_end IS NULL))',
    'CHECK (source_start IS NULL OR source_start >= 0)',
    'CHECK (source_start IS NULL OR source_end > source_start)',
    // Lo copiado sabe siempre de dónde salió; lo editado es solo lo copiado.
    "CHECK (origin <> 'copied' OR source_start IS NOT NULL)",
    "CHECK (origin = 'copied' OR edited = 0)",
    // La persona escribe de cero solo notas; lo estudiado en el procesado es
    // resumen, síntesis o palabras clave, y sabe dónde está (decisión I).
    "CHECK (origin <> 'user' OR section = 'notes')",
    // Una sola línea a propósito: drift solo lee el texto de una restricción
    // si es un literal entero, y uno de varios renglones cambiaría con el fin
    // de línea de cada copia del repositorio.
    // ignore: lines_longer_than_80_chars
    "CHECK (origin NOT IN ('studied', 'chosen') OR section IN ('summary', 'synthesis', 'keywords'))",

    'CHECK ((text_start IS NULL) = (text_end IS NULL))',
    'CHECK (text_start IS NULL OR text_start >= 0)',
    'CHECK (text_start IS NULL OR text_end > text_start)',
    // Las palabras clave llevan sus tramos, y solo ellas.
    "CHECK ((spans IS NOT NULL) = (section = 'keywords'))",
  ];
}
