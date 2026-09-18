import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';

/// Una propuesta del modelo de lenguaje, siempre confirmable: nunca
/// escribe nada por su cuenta, solo queda acá hasta que alguien la acepte
/// o la descarte —ver `SuggestionRepository`—.
///
/// `targetItemId` referencia el modelo NUEVO (`KnowledgeEntries`, SQL
/// `item`), no la vieja `Items`: son el mismo id para todo elemento que
/// pasó por el espejo de F3, y la Bandeja de entrada —donde esto se
/// revisa— ya vive del lado del modelo nuevo.
@DataClassName('SuggestionRow')
@TableIndex(
  name: 'idx_suggestions_target_status',
  columns: {#targetItemId, #status},
)
class Suggestions extends Table {
  TextColumn get id => text()();

  TextColumn get kind => textEnum<SuggestionKind>()();

  TextColumn get targetItemId => text().references(
    KnowledgeEntries,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// La propuesta en sí, codificada a mano —sin paquete nuevo, mismo
  /// criterio que `content_block.dart`—: hoy solo existe la forma
  /// `property` (`{definitionId, definitionName, value, isNewValue}`).
  TextColumn get payloadJson => text()();

  RealColumn get confidence => real().nullable()();

  TextColumn get status =>
      textEnum<SuggestionStatus>().withDefault(const Constant('pending'))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
