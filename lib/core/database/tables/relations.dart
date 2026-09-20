import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/knowledge_entries.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

/// Los vínculos entre elementos: lo que convierte una pila de recortes en una
/// red.
@DataClassName('RelationRow')
@TableIndex(name: 'idx_relations_from', columns: {#fromItemId})
@TableIndex(name: 'idx_relations_to', columns: {#toItemId})
class Relations extends Table {
  TextColumn get id => text()();

  TextColumn get fromItemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get toItemId =>
      text().references(KnowledgeEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<RelationKind>()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Cuándo se marcó como revisada. `null` = sin revisar. Hoy solo importa
  /// para `contradicts`: es lo que cuenta el indicador "contradicciones sin
  /// revisar" del panel de salud y lo que la pantalla de Tensión marca.
  DateTimeColumn get reviewedAt => dateTime().nullable()();

  /// DÓNDE del texto de la fuente (`toItemId`) sale esta relación, cuando se
  /// sabe: desplazamientos de caracteres, los mismos que usan los `Chunks`.
  /// Los guarda la extracción de una nota desde una selección; de ahí salen
  /// el timestamp o la página de una cita. `null` = no se sabe dónde.
  IntColumn get sourceCharStart => integer().nullable()();
  IntColumn get sourceCharEnd => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // El mismo vínculo, del mismo tipo, entre los mismos dos elementos, una
    // sola vez.
    'UNIQUE (from_item_id, to_item_id, kind)',
    // Nada se relaciona consigo mismo: sería una línea que no dice nada y que
    // ensucia cualquier recorrido del grafo.
    'CHECK (from_item_id <> to_item_id)',
  ];
}
