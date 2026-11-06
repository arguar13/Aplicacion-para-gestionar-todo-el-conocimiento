import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/processed_documents.dart';
import 'package:sinapsis/core/database/tables/processed_images.dart';
import 'package:sinapsis/core/domain/entities/index_entry_origin.dart';

/// Una entrada del Índice (F46, v51, decisión F): un capítulo de un documento
/// procesado, con su nivel, su título y su lugar, como el índice automático de
/// Word; la entrada «Texto completo» de un texto sin títulos; o una imagen del
/// documento, con su título.
///
/// **Es derivada**: sale toda de lo que ya está en Procesado —las páginas de la
/// sección «Texto», el PDF del documento y sus imágenes— y se puede borrar y
/// rehacer entera sin perder nada. De la Biblioteca solo se puede leer un PDF,
/// nunca escribir nada. Por eso no viaja en la unión de bóvedas (cada base la
/// rehace de lo suyo) y no guarda dos veces lo que ya está en otro lado: el
/// nombre del documento y sus temas se leen de donde están.
///
/// - **Los capítulos y «Texto completo»** los escribe
///   `ProcessedHeadingsIndexer`, en la misma transacción que el texto, y solo
///   los de ese documento: lo que lee el paso 1 (`ProcessedHeading`), fila por
///   fila. Una invariante los hace confiables: **un documento con texto tiene
///   al menos una entrada de texto** —sus capítulos o «Texto completo»—.
///   Cualquier escritura que cambie lo que los produce —una página del texto,
///   su lugar o su ancla, o la copia del original— borra las de su documento
///   en el acto (`processedHeadingStaleTriggers`): un documento con texto y
///   sin entradas de texto está «sin indexar», y nunca se ven entradas viejas.
///   El relleno (`ProcessedHeadingsBackfill`) rehace los que quedan así.
/// - **Las imágenes** las mantiene la base sola, desde `processed_images`: una
///   entrada por imagen ya titulada (`processedImageHeadingTriggers`), que se
///   va con la imagen.
/// - Se busca por su propio índice de texto (`processed_heading_search`, FTS5
///   de contenido externo por [rowKey], como `processed_part_search`).
@DataClassName('ProcessedHeadingRow')
//
// Las entradas de un documento se leen en su orden; las cuentas de
// capítulos, el estado del documento y los padres de lo que se encuentra
// —«el título anterior de nivel más alto»— se resuelven en el mismo índice,
// sin volver a la tabla: por eso lleva el origen y el nivel.
@TableIndex(
  name: 'idx_processed_headings_document',
  columns: {#documentId, #position, #origin, #level},
)
class ProcessedHeadings extends Table {
  @override
  String get tableName => 'processed_headings';

  /// La clave entera que usa el índice de texto para volver a la fila: ver
  /// `Chunks.rowKey` para por qué no puede ser el `rowid` implícito.
  IntColumn get rowKey => integer().autoIncrement()();

  TextColumn get documentId => text().references(
    ProcessedDocuments,
    #itemId,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get origin => textEnum<IndexEntryOrigin>()();

  /// El nivel corrido (`ProcessedHeading.level`): el primero es el 1 y ninguno
  /// salta uno respecto del que lo contiene.
  IntColumn get level => integer()();

  /// El orden dentro del documento entre los de su clase, de 0 en adelante:
  /// los capítulos en el orden en que se leen (`ProcessedHeading.order`); una
  /// imagen, su lugar en la galería.
  IntColumn get position => integer()();

  /// El título, tal como se lee. Vacío en «Texto completo» y en una imagen
  /// cuya fuente no dice nada de ella: el nombre lo pone la pantalla.
  TextColumn get title => text()();

  /// El tramo del título en el texto propio del documento —sus páginas de
  /// «Texto», una detrás de la otra—, donde lo abre el lector, y la página
  /// del texto procesado donde cae, de 1 en adelante (la «Página 3 de 6» del
  /// lector). Los tres juntos o ninguno: un marcador que no se encontró en el
  /// texto no los tiene, y una imagen tampoco.
  IntColumn get textStart => integer().nullable()();
  IntColumn get textEnd => integer().nullable()();
  IntColumn get textPage => integer().nullable()();

  /// La página real del PDF, de 1 en adelante: la de un marcador, o la del PDF
  /// donde cae un título de la IA (decisión C). `null` en lo que no es un PDF
  /// o si no se sabe.
  IntColumn get pdfPage => integer().nullable()();

  /// La imagen de una entrada de imagen —su forma, la clave de
  /// `processed_images`—; `null` en las demás.
  TextColumn get imageId => text().nullable().unique().references(
    ProcessedImages,
    #renditionId,
    onDelete: KeyAction.cascade,
  )();

  @override
  List<String> get customConstraints => [
    'CHECK (level >= 1)',
    'CHECK (position >= 0)',
    // El tramo y su página van juntos o no van (`ProcessedHeading`).
    'CHECK ((text_start IS NULL) = (text_end IS NULL))',
    'CHECK ((text_start IS NULL) = (text_page IS NULL))',
    'CHECK (text_start IS NULL OR text_start >= 0)',
    'CHECK (text_end IS NULL OR text_end >= text_start)',
    'CHECK (text_page IS NULL OR text_page >= 1)',
    'CHECK (pdf_page IS NULL OR pdf_page >= 1)',
    // Una imagen, con su imagen y nada del texto; lo demás, sin imagen.
    "CHECK ((image_id IS NOT NULL) = (origin = 'image'))",
    // Una sola línea a propósito: drift solo lee el texto de una restricción
    // si es un literal entero (ver `ProcessedParts`).
    // ignore: lines_longer_than_80_chars
    "CHECK (origin <> 'image' OR (text_start IS NULL AND pdf_page IS NULL AND level = 1))",
    // Un capítulo siempre dice algo; sin título, solo «Texto completo» y una
    // imagen que no dice nada.
    "CHECK (length(title) > 0 OR origin IN ('wholeText', 'image'))",
    "CHECK (origin <> 'wholeText' OR (length(title) = 0 AND level = 1))",
  ];
}
