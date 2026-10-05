import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/trashed_content_kind.dart';

/// La papelera del contenido (F30, v38, decisión 68): lo que se soltó de un
/// elemento —su archivo original o su texto— y se puede recuperar durante
/// 30 días; pasado ese tiempo se borra de verdad.
///
/// No es la papelera de los elementos (`item.deleted_at`): el elemento sigue
/// vivo en la Biblioteca, con lo que se quedó. Al triar un libro se elige qué
/// pasa a la siguiente fase —el texto, el libro o los dos—, y lo que no pasa
/// espera acá.
///
/// - **Un archivo** no se mueve: queda en el disco donde estaba
///   ([relativePath]) y la fuente deja de apuntarle. Recuperarlo es volver a
///   apuntarle; vencido, se borra del disco si nada más lo usa.
/// - **Un texto** se guarda entero —el contenido, su clase, si era el
///   principal, cuándo se escribió, los tiempos de cada palabra— con sus
///   subrayados ([highlights]), que en la base cuelgan de la forma y se irían
///   con ella. Recuperarlo vuelve a poner la misma forma, con el mismo
///   identificador, y sus subrayados.
///
/// Es de este dispositivo: el archivo vive en su disco. **No viaja al
/// fusionar bóvedas** —ver la decisión 68—, y se va con su elemento cuando
/// el elemento se borra para siempre (quien lo borra se lleva el archivo).
@DataClassName('TrashedContentRow')
@TableIndex(name: 'idx_content_trash_item', columns: {#itemId})
@TableIndex(name: 'idx_content_trash_trashed_at', columns: {#trashedAt})
class TrashedContents extends Table {
  @override
  String get tableName => 'content_trash';

  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<TrashedContentKind>()();

  // --- Un archivo ----------------------------------------------------------

  /// Dónde está el archivo, relativo al directorio de datos de la app: el
  /// mismo lugar donde estaba cuando la fuente le apuntaba.
  TextColumn get relativePath => text().nullable()();

  /// Cuánto pesa, en bytes, para decir cuánto se libera. Nulo si no se pudo
  /// medir.
  IntColumn get sizeBytes => integer().nullable()();

  // --- Un texto: la forma tal como estaba ----------------------------------

  /// El identificador que tenía la forma: recuperarla le devuelve el mismo, y
  /// con él vuelven a valer los subrayados y lo que apuntaba a ese texto.
  TextColumn get renditionId => text().nullable()();

  TextColumn get renditionKind => textEnum<RenditionKind>().nullable()();

  /// El texto, entero.
  TextColumn get content => text().nullable()();

  BoolColumn get isPrimary => boolean().nullable()();

  DateTimeColumn get renditionCreatedAt => dateTime().nullable()();

  /// Los tiempos de cada palabra de una transcripción, como los guarda
  /// `renditions.word_timings`.
  TextColumn get wordTimings => text().nullable()();

  /// Los subrayados de la forma, en JSON —ver `encodeTrashedHighlights`—.
  TextColumn get highlights => text().nullable()();

  /// Cuándo se soltó: a los 30 días se borra de verdad.
  DateTimeColumn get trashedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // Un archivo tiene dónde está; un texto, su contenido y su forma.
    "CHECK ((kind = 'file') = (relative_path IS NOT NULL))",
    "CHECK ((kind = 'text') = (content IS NOT NULL))",
    // Y un texto, todo lo que hace falta para volver a poner su forma.
    "CHECK (kind <> 'text' OR rendition_id IS NOT NULL)",
    "CHECK (kind <> 'text' OR rendition_kind IS NOT NULL)",
    "CHECK (kind <> 'text' OR is_primary IS NOT NULL)",
    "CHECK (kind <> 'text' OR rendition_created_at IS NOT NULL)",
  ];
}
