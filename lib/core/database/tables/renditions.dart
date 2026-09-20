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

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((content IS NULL) <> (relative_path IS NULL))',
  ];
}
