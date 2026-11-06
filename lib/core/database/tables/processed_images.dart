import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/processed_documents.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';

/// Una imagen de un documento procesado (F41, v47, decisión L): una copia
/// propia de una imagen de su fuente —el archivo de una imagen guardada, una
/// foto de una página o de una publicación—, elegida una por una al triar.
///
/// El archivo es una forma (`renditions`) del procesado —con su ruta, su tipo,
/// su peso y su nombre—, como la copia del original (decisión H), así que
/// viaja como cualquier archivo de la bóveda: lo cuentan `isFileReferenced`,
/// la copia de la bóveda (vive en `originales/<procesado>/imagenes/`), la
/// unión (`OriginalFilesMerge` copia lo que referencia una forma), la papelera
/// y el borrado de verdad. Su forma no tiene `position`: no es «Contenido»
/// bajado, y nada la lee ni la transcribe. Esta fila le agrega lo que la hace
/// una imagen del procesado:
///
/// - su lugar en la galería ([position]);
/// - de qué archivo de la fuente salió y cuánto pesaba ([sourceFilePath],
///   [sourceFileSize]): es lo que dice, al volver a triar, que una imagen ya
///   está —nunca se copia dos veces la misma, lo garantiza la base—.
///
/// Su id de forma sale del documento y del archivo de la fuente
/// (`processedImageRenditionIdFor`): dos dispositivos que copian la misma
/// imagen al mismo procesado llegan a la misma forma. Se va con su forma;
/// soltar el archivo de la fuente no la toca, y al revés.
@DataClassName('ProcessedImageRow')
@TableIndex(
  name: 'idx_processed_images_document',
  columns: {#documentId, #position},
)
class ProcessedImages extends Table {
  @override
  String get tableName => 'processed_images';

  /// La forma del procesado con el archivo copiado.
  TextColumn get renditionId =>
      text().references(Renditions, #id, onDelete: KeyAction.cascade)();

  TextColumn get documentId => text().references(
    ProcessedDocuments,
    #itemId,
    onDelete: KeyAction.cascade,
  )();

  /// El orden en la galería, de 0 en adelante.
  IntColumn get position => integer()();

  /// El archivo de la fuente que se copió, y cuánto pesaba.
  TextColumn get sourceFilePath => text()();
  IntColumn get sourceFileSize => integer()();

  DateTimeColumn get copiedAt => dateTime()();

  /// Su título (F46, v51, decisión E), el de su entrada en el Índice: lo que
  /// dice de ella la fuente —su pie de foto, su texto alternativo, el título
  /// bajo el que está— o, si no dice nada, el nombre de su archivo, limpio
  /// («Mapa del Imperio romano», no `mapa_imperio-romano_02.jpg`): ver
  /// `processedImageTitle`. Se pone al triar y se puede renombrar.
  ///
  /// - Vacío si nada dice nada —un `IMG_2034.jpg` sin texto alternativo—: la
  ///   pantalla la nombra por su lugar («Imagen 3»).
  /// - `null` si todavía no se la tituló: una imagen de antes de v51, o una
  ///   que vuelve de la papelera soltada antes, hasta que el relleno del
  ///   Índice (`ProcessedHeadingsBackfill`) le pone su título.
  ///
  /// Nunca con espacios en los bordes: un título en blanco es vacío.
  TextColumn get title =>
      text().nullable()
      // La restricción se refiere a la propia columna: es el modo de drift de
      // escribir un `CHECK`, y el analizador lo toma por una recursión.
      // ignore: recursive_getters
      .check(title.trim().equalsExp(title))();

  @override
  Set<Column<Object>> get primaryKey => {renditionId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {documentId, sourceFilePath},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (position >= 0)',
    'CHECK (source_file_size >= 0)',
  ];
}
