import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/habit/data/services/habit_activity_days.dart';
import 'package:sinapsis/features/habit/domain/entities/streak.dart';
import 'package:sinapsis/features/habit/domain/repositories/streak_repository.dart';
import 'package:sinapsis/features/habit/domain/services/streak_calculator.dart';

/// [StreakRepository] sobre la base (F17, D6): dedica el cálculo en sí a
/// [calculateStreak], puro, sobre los días que da [HabitActivityDays]
/// —compartidos con `BadgeRepositoryImpl` (F17, commit 9)—. [watch] es la
/// misma lectura, reactiva a las cinco tablas de las que salen esos días
/// (commit 8).
class StreakRepositoryImpl implements StreakRepository {
  const StreakRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;

  @override
  Future<Streak> current() async {
    final activeDays = await HabitActivityDays(_db).all();
    return calculateStreak(activeDays, today: _clock());
  }

  @override
  Stream<Streak> watch() {
    return watchQuery(
      db: _db,
      tables: [
        _db.reviewLogs,
        _db.fieldVersions,
        _db.knowledgeEntries,
        _db.knowledgeNotes,
        _db.habitEvents,
      ],
      read: current,
      telemetry: _telemetry,
      hint: 'StreakRepositoryImpl.watch',
    );
  }
}
