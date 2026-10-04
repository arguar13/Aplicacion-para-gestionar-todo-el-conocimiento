import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

/// Cada forma en que existe el contenido de un elemento.
///
/// `content` y `relativePath` son ambas anulables, pero exactamente una tiene
/// que estar llena. Eso lo garantiza un CHECK de SQLite y no un comentario:
/// la entidad de dominio `Rendition` hace imposible construir un estado
/// inválido, y esta restricción cierra la otra puerta —que alguien escriba
/// directamente en la base o que un error de mapeo lo cuele—.
@DataClassName('RenditionRow')
@TableIndex(name: 'idx_renditions_item', columns: {#itemId})
@TableIndex(name: 'idx_renditions_text_of', columns: {#textOf})
class Renditions extends Table {
  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<RenditionKind>()();

  /// El texto, para las formas de texto. Vive en la base porque es lo que se
  /// busca e indexa.
  TextColumn get content => text().nullable()();

  /// Ruta **relativa** al directorio de datos de la app, para las formas que
  /// son archivos.
  ///
  /// Relativa y no absoluta a propósito: en iOS y Android el contenedor de la
  /// app cambia de ruta entre instalaciones y actualizaciones, así que una
  /// ruta absoluta guardada hoy puede apuntar a la nada mañana.
  TextColumn get relativePath => text().nullable()();

  BoolColumn get isPrimary => boolean()();
  DateTimeColumn get createdAt => dateTime()();

  /// En una transcripción, cuándo se dice cada palabra (F23): JSON con dos
  /// listas paralelas, las palabras y su momento en milisegundos —ver
  /// `encodeWordTimings`—. Nulo si no se midió: es lo que hay en todo lo
  /// anterior a F23 y en todo lo que no es una transcripción.
  TextColumn get wordTimings => text().nullable()();

  // --- El contenido bajado de una página (F30, v36) -----------------------
  //
  // Una página o una publicación trae, además de su texto, archivos: las
  // fotos del artículo, los PDF y los audios que enlaza, los videos que
  // incrusta. Cada uno es una forma más del elemento —un archivo, en su
  // formato original— con lo que hace falta para mostrarlo en la sección
  // «Contenido» y para saber de dónde salió. En las formas de antes, y en
  // las que no son contenido bajado, todo esto es nulo.

  /// El nombre con el que se muestra: el texto alternativo de una foto, el
  /// texto del enlace a un PDF, el nombre del archivo.
  TextColumn get title => text().nullable()();

  /// De dónde se bajó.
  TextColumn get originUrl => text().nullable()();

  /// El tipo que dijo el servidor (`application/pdf`, `audio/mpeg`).
  TextColumn get mimeType => text().nullable()();

  /// Cuánto pesa el archivo, en bytes.
  IntColumn get sizeBytes => integer().nullable()();

  /// En qué orden aparece en la página. Que no sea nulo es lo que hace de un
  /// archivo parte del «Contenido»: el texto del elemento y la página
  /// archivada no lo llevan.
  IntColumn get position => integer().nullable()();

  /// En una forma de texto: de qué archivo del «Contenido» es el texto —lo
  /// extraído de un libro, la transcripción de un audio, lo leído en una
  /// foto—. Se va con su archivo.
  TextColumn get textOf => text().nullable().references(
    Renditions,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((content IS NULL) <> (relative_path IS NULL))',
  ];
}
