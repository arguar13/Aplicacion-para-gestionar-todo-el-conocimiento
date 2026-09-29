import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/processing_checkpoint_kind.dart';

/// El avance guardado de un trabajo largo sobre un elemento (F21): cada
/// página ya reconocida de un libro escaneado, cada tramo ya transcrito de
/// un audio de horas. Si la app se cierra —o el sistema la mata— a mitad de
/// camino, al volver se sigue desde lo que ya está acá, no desde cero.
///
/// Es estado de trabajo, no contenido del usuario: al terminar, lo reunido
/// pasa a la forma de texto del elemento y estas filas se borran. Tampoco
/// viaja al fusionar bóvedas —un trabajo a medias en otro dispositivo se
/// retoma allá, o se rehace acá—, y se va solo con el elemento si se lo
/// borra.
@DataClassName('ProcessingCheckpointRow')
class ProcessingCheckpoints extends Table {
  @override
  String get tableName => 'processing_checkpoint';

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  /// Qué trabajo: reconocer páginas, transcribir tramos.
  TextColumn get kind => textEnum<ProcessingCheckpointKind>()();

  /// Qué parte: el número de página, o de tramo, desde 0.
  IntColumn get position => integer()();

  /// Lo que salió de esa parte: el texto reconocido o transcrito. Vacío es
  /// un resultado válido —una página en blanco—, distinto de "todavía no
  /// se hizo", que es que no haya fila.
  TextColumn get content => text()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, kind, position};
}
