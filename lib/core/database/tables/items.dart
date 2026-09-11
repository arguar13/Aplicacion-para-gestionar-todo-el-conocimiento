import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/tables/sources.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';

/// El elemento guardado.
///
/// Los índices de abajo no son adorno: son exactamente las columnas por las
/// que la biblioteca filtra y ordena. Sin ellos, cada listado recorre la
/// tabla entera, que con cien elementos no se nota y con veinte mil sí.
@DataClassName('ItemRow')
@TableIndex(name: 'idx_items_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_items_updated_at', columns: {#updatedAt})
@TableIndex(name: 'idx_items_processing_state', columns: {#processingState})
@TableIndex(name: 'idx_items_source', columns: {#sourceId})
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Borrar la fuente borra el elemento. No es una decisión de conveniencia:
  /// un elemento sin fuente sería justamente lo que esta app promete que no
  /// va a pasar — contenido que no puede decir de dónde salió.
  TextColumn get sourceId =>
      text().references(Sources, #id, onDelete: KeyAction.cascade)();

  TextColumn get processingState => textEnum<ProcessingState>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
