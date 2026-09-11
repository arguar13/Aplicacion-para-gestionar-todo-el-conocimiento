import 'package:drift/drift.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';

/// De dónde vino cada elemento.
///
/// Las clases de fila llevan el sufijo `Row` para no chocar con las entidades
/// de dominio del mismo nombre. No son lo mismo y conviene que se note: esta
/// es una fila plana, `Source` es la entidad que el resto de la app usa.
@DataClassName('SourceRow')
class Sources extends Table {
  TextColumn get id => text()();

  /// Se guarda como texto y no como número: un entero convierte cualquier
  /// volcado de la base en un jeroglífico, y reordenar el enum en el código
  /// reasignaría silenciosamente el significado de las filas ya guardadas.
  TextColumn get kind => textEnum<SourceKind>()();

  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get url => text().nullable()();
  TextColumn get authorName => text().nullable()();
  TextColumn get authorUrl => text().nullable()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  TextColumn get originalFilePath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
