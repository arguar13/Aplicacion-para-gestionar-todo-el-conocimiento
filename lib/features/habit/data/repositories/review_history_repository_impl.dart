import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_reader.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/repositories/review_history_repository.dart';
import 'package:sinapsis/features/habit/domain/services/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/true_retention.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';

/// Cuántas tarjetas trae «Tarjetas difíciles», ya recortado. Decisión
/// propia: diez alcanza para señalar un patrón sin abrumar la pantalla.
const kHardestCardsLimit = 10;

/// Por debajo de esto no cuenta: una tarjeta repasada una sola vez y
/// calificada «De nuevo» tendría 100 % sin decir nada real. Decisión propia:
/// un piso bajo para que un caso mínimo no trivialice el criterio.
const kHardestCardsMinReviews = 3;

/// [ReviewHistoryRepository] sobre la base (F17, D8; F43, M16).
///
/// Dos lecturas en lote, con el recorte resuelto una vez: las respuestas
/// agrupadas por cuarto de hora —de donde salen la curva, la retención real,
/// el calendario y las rachas, con todo el historial— y las difíciles. Una
/// tarjeta de un elemento en la papelera no cuenta: ya no se puede repasar.
class ReviewHistoryRepositoryImpl implements ReviewHistoryRepository {
  ReviewHistoryRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
    required StudyScopeResolver resolver,
    StudyDay day = const StudyDay(),
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock,
       _day = day,
       _reader = ReviewScopeReader(database: database, resolver: resolver);

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;
  final StudyDay _day;
  final ReviewScopeReader _reader;

  @override
  Future<ReviewHistory> current(StudyScope scope) async {
    final now = _clock();
    final sql = await _reader.sqlFor(scope);
    final activity = await _reader.activity(sql);
    final runs = studyRuns(activity, now: now, day: _day);

    return ReviewHistory(
      retentionByWeek: weeklyRetention(activity, now: now, day: _day),
      trueRetention: trueRetention(activity, now: now, day: _day),
      hardestCards: await _hardestCards(sql),
      activityByDay: dailyActivity(activity, now: now, day: _day),
      currentRun: runs.current,
      longestRun: runs.longest,
    );
  }

  Future<List<DifficultCard>> _hardestCards(ReviewScopeSql sql) async {
    final rows = await _reader.rows(
      sql.difficult(
        minReviews: kHardestCardsMinReviews,
        limit: kHardestCardsLimit,
      ),
    );
    return [
      for (final row in rows)
        DifficultCard(
          flashcardId: row.read<String>('flashcard_id'),
          front: row.read<String>('front'),
          back: row.read<String>('back'),
          itemId: row.read<String>('item_id'),
          total: row.read<int>('total'),
          againCount: row.read<int>('again_count'),
          lapses: row.read<int>('lapses'),
          sourceStart: row.readNullable<int>('source_start'),
          sourceEnd: row.readNullable<int>('source_end'),
        ),
    ];
  }

  @override
  Stream<ReviewHistory> watch(StudyScope scope) {
    return watchQuery(
      db: _db,
      tables: _reader.watched,
      read: () => current(scope),
      telemetry: _telemetry,
      hint: 'ReviewHistoryRepositoryImpl.watch',
    );
  }
}
