import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/items.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';

/// Los vínculos entre elementos: lo que convierte una pila de recortes en una
/// red.
@DataClassName('RelationRow')
@TableIndex(name: 'idx_relations_from', columns: {#fromItemId})
@TableIndex(name: 'idx_relations_to', columns: {#toItemId})
class Relations extends Table {
  TextColumn get id => text()();

  TextColumn get fromItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get toItemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<RelationKind>()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

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
