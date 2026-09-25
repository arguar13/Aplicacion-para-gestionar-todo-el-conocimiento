import 'package:drift/drift.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';

/// Un rastro mínimo de una acción que cuenta para la racha (F17, D6) y que
/// ningún otro lado del esquema ya guarda con fecha: ver [HabitEventKind].
///
/// No referencia ningún elemento ni ninguna otra fila a propósito: lo único
/// que hace falta para la racha es saber que algo de este tipo pasó, y
/// cuándo. Se une entre bóvedas igual que `review_log` —por [id], nunca se
/// pisa ni se borra—.
@DataClassName('HabitEventRow')
@TableIndex(name: 'idx_habit_events_occurred', columns: {#occurredAt})
class HabitEvents extends Table {
  @override
  String get tableName => 'habit_event';

  TextColumn get id => text()();

  TextColumn get kind => textEnum<HabitEventKind>()();

  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
