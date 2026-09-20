import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';

/// Un conflicto que una fusión de bóvedas detectó y dejó para que lo revise el
/// usuario (F11): el mismo campo del mismo elemento, modificado en las dos
/// bóvedas sin que ninguna partiera de la versión de la otra.
///
/// Jamás se pisa contenido en silencio: la versión más reciente queda en vivo y
/// la otra se guarda acá. En un campo corto, las dos versiones viven en
/// [localValue] e [incomingValue]. En el TEXTO de una forma, la versión
/// entrante no se copia acá —puede ser un documento entero—: entra como otra
/// forma del mismo elemento, no principal, y [otherRenditionId] la señala.
///
/// [resolvedAt] nulo = pendiente. [resolution] dice cómo se resolvió:
/// `keepLocal`, `useIncoming` o `keepBoth`.
@DataClassName('MergeConflictRow')
@TableIndex(name: 'idx_merge_conflict_resolved', columns: {#resolvedAt})
@TableIndex(name: 'idx_merge_conflict_item', columns: {#itemId})
class MergeConflicts extends Table {
  @override
  String get tableName => 'merge_conflict';

  TextColumn get id => text()();

  TextColumn get itemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get fieldName => text()();

  TextColumn get localValue => text().nullable()();

  TextColumn get incomingValue => text().nullable()();

  /// La forma que guarda la versión entrante de un texto. Si esa forma se
  /// borra, el conflicto sigue existiendo —con la referencia en nulo—.
  TextColumn get otherRenditionId => text().nullable().references(
    Renditions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get localUpdatedAt => dateTime().nullable()();

  TextColumn get localDeviceId => text().nullable()();

  DateTimeColumn get incomingUpdatedAt => dateTime().nullable()();

  TextColumn get incomingDeviceId => text().nullable()();

  DateTimeColumn get detectedAt => dateTime()();

  DateTimeColumn get resolvedAt => dateTime().nullable()();

  TextColumn get resolution => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
