import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/spaces.dart';
import 'package:sinapsis/core/domain/entities/item_kind.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';

/// El núcleo común a toda fuente o nota: identidad, título, a qué espacio
/// pertenece, y en qué estado de trabajo intelectual está.
///
/// El nombre SQL es `item` (no `knowledge_entries`) porque es el
/// vocabulario que usa el resto del modelo —`source`/`note` y todo lo que
/// cuelga de un elemento referencian `item`—; la clase Dart se llama
/// `KnowledgeEntries` por el nombre que tuvo mientras convivía con la tabla
/// vieja `items`, que F10 retiró: ver la decisión sobre el modelo Fuente/Nota
/// en docs/arquitectura.md.
@DataClassName('KnowledgeEntryRow')
@TableIndex(name: 'idx_knowledge_entries_state_kind', columns: {#state, #kind})
@TableIndex(name: 'idx_knowledge_entries_space', columns: {#spaceId})
@TableIndex(name: 'idx_knowledge_entries_updated_at', columns: {#updatedAt})
@TableIndex(
  name: 'idx_knowledge_entries_kind_updated',
  columns: {#kind, #updatedAt},
)
class KnowledgeEntries extends Table {
  @override
  String get tableName => 'item';

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();

  /// El texto libre que el usuario escribe junto a un elemento. Vivía en la
  /// tabla vieja `items`; F10 lo pasó acá al retirarla.
  TextColumn get notes => text().nullable()();
  TextColumn get spaceId =>
      text().nullable().references(Spaces, #id, onDelete: KeyAction.setNull)();
  TextColumn get kind => textEnum<ItemKind>()();
  TextColumn get state => textEnum<ItemState>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Preparado para cuando exista sync de verdad. Nada lo escribe ni lo
  /// lee todavía: el borrado sigue siendo DELETE físico con cascada real,
  /// igual que en el esquema viejo.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Ídem: identidad de qué dispositivo escribió este elemento, para
  /// cuando exista sync. Ningún código de F1 lo lee.
  TextColumn get deviceId => text()();
  IntColumn get rev => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
