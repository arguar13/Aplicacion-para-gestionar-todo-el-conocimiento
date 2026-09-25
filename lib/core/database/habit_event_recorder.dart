import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/habit_event_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';

/// Guarda un [HabitEventKind] en `habit_event` (F17, D6): triar la Bandeja,
/// resolver algo en Vocabulario.
///
/// Sin `Either`, a propósito: un evento de hábito es información
/// secundaria para la racha, no el dato que la persona vino a guardar —que
/// esto falle no puede tumbar la aceptación de una sugerencia ni una
/// fusión de vocabulario que sí salieron bien—. Si la escritura falla, se
/// reporta a telemetría y se sigue.
class HabitEventRecorder {
  const HabitEventRecorder({
    required AppDatabase database,
    required TelemetryService telemetry,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final IdGenerator _ids;
  final Clock _clock;

  Future<void> record(HabitEventKind kind) async {
    try {
      await _db
          .into(_db.habitEvents)
          .insert(
            HabitEventsCompanion.insert(
              id: _ids.next(),
              kind: kind,
              occurredAt: _clock(),
            ),
          );
      // Ver la clase: un evento de hábito nunca revienta la acción real.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(e, stackTrace, hint: 'HabitEventRecorder.record');
    }
  }
}
