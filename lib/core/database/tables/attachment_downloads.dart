import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/domain/entities/attachment_download_status.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';

/// Los archivos que ofrece una página y en qué quedó cada uno (F30, v36):
/// la lista de trabajo de «bajar todo».
///
/// Al leer una página se anota acá cada foto, documento, audio o video que
/// se encontró en el cuerpo del artículo; después se bajan de a uno, y cada
/// uno queda bajado, afuera por el tope —lo que «Bajar el resto» retoma—,
/// sin lugar o fallido. Como cada paso queda escrito, cerrar la app a mitad
/// de camino no hace volver a bajar lo que ya está.
///
/// Es estado de trabajo de este dispositivo, como `processing_checkpoint`:
/// **no viaja al fusionar bóvedas**. Lo que sí viaja es lo bajado —las formas
/// del «Contenido» y sus archivos—; lo que quedó afuera en otro teléfono se
/// vuelve a ofrecer allá. Se va con su elemento.
@DataClassName('AttachmentDownloadRow')
@TableIndex(name: 'idx_attachment_downloads_item', columns: {#itemId})
class AttachmentDownloads extends Table {
  @override
  String get tableName => 'attachment_download';

  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// La dirección del archivo, completa.
  TextColumn get url => text()();

  /// Qué se espera que sea, por cómo aparece en la página: una foto, un
  /// audio, un documento… El servidor puede decir otra cosa al bajarlo, y
  /// manda lo que diga el servidor.
  TextColumn get kind => textEnum<RenditionKind>()();

  /// El nombre con que se lo ofrece: el texto del enlace, el texto
  /// alternativo de la foto.
  TextColumn get title => text().nullable()();

  /// En qué orden aparece en la página.
  IntColumn get position => integer()();

  TextColumn get status => textEnum<AttachmentDownloadStatus>()();

  /// La persona pidió «Bajar el resto»: el tope por elemento no se le aplica.
  BoolColumn get forced => boolean().withDefault(const Constant(false))();

  /// Cuánto dijo el servidor que pesa, si llegó a decirlo.
  IntColumn get expectedBytes => integer().nullable()();

  /// La forma del «Contenido» en que quedó, cuando se bajó. Si se borra esa
  /// forma, la fila queda sin ella y no se vuelve a bajar sola.
  TextColumn get renditionId => text().nullable().references(
    Renditions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {itemId, url},
  ];
}
