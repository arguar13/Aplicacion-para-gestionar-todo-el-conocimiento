import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/renditions.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';

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

  /// El color que eligió la persona (F38, v42). `null` en todos los de antes
  /// —y en los que se hacen sin elegir—: se ven con el color de siempre.
  TextColumn get color => textEnum<HighlightColor>().nullable()();

  /// Fondo pintado o línea debajo (F38, v42). Los de antes, fondo.
  TextColumn get style => textEnum<HighlightStyle>().withDefault(
    Constant(HighlightStyle.fill.name),
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (end_offset > start_offset)',
    'CHECK (start_offset >= 0)',
  ];
}
