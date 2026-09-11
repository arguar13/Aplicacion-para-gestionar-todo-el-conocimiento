import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';

/// Los fragmentos subrayados, con su nota.
@DataClassName('HighlightRow')
@TableIndex(name: 'idx_highlights_rendition', columns: {#renditionId})
class Highlights extends Table {
  TextColumn get id => text()();

  /// Apunta a una rendition y no a un elemento: un subrayado pertenece a un
  /// texto concreto, con sus posiciones concretas. El mismo contenido puede
  /// existir como transcripción y como artículo, y las posiciones de uno no
  /// significan nada en el otro.
  TextColumn get renditionId =>
      text().references(Renditions, #id, onDelete: KeyAction.cascade)();

  IntColumn get startOffset => integer()();
  IntColumn get endOffset => integer()();

  /// El texto subrayado, copiado. Redundante con las posiciones a propósito:
  /// si la rendition se regenera —una transcripción rehecha con un modelo
  /// mejor— los índices dejan de apuntar donde apuntaban, y sin esta copia el
  /// subrayado se perdería.
  TextColumn get excerpt => text()();

  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (end_offset > start_offset)',
    'CHECK (start_offset >= 0)',
  ];
}
