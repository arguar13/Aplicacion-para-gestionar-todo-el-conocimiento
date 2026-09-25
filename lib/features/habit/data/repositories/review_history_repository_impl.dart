import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_grade.dart';
import 'package:sinapsis/features/habit/data/repositories/review_history_query_sql.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/repositories/review_history_repository.dart';
import 'package:sinapsis/features/habit/domain/services/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';

/// [ReviewHistoryRepository] sobre la base (F17, D8).
class ReviewHistoryRepositoryImpl implements ReviewHistoryRepository {
  const ReviewHistoryRepositoryImpl({
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
  Future<ReviewHistory> current() async {
    final today = _clock();
    final todayDate = DateTime(today.year, today.month, today.day);
    final cutoff = todayDate.subtract(
      const Duration(days: kReviewHistoryDays - 1),
    );

    final logs = _db.reviewLogs;
    final rows =
        await (_db.selectOnly(logs)
              ..addColumns([logs.reviewedAt, logs.grade])
              ..where(logs.reviewedAt.isBiggerOrEqualValue(cutoff)))
            .get();

    final reviews = [
      for (final row in rows)
        (
          reviewedAt: row.read(logs.reviewedAt)!,
          retained: _isRetained(row.read(logs.grade)!),
        ),
    ];

    return ReviewHistory(
      retentionByWeek: weeklyRetention(reviews, today: today),
      hardestCards: await _hardestCards(),
      activityByDay: dailyActivity([
        for (final review in reviews) review.reviewedAt,
      ], today: today),
    );
  }

  bool _isRetained(String grade) =>
      grade == ReviewGrade.good.name || grade == ReviewGrade.easy.name;

  Future<List<DifficultCard>> _hardestCards() async {
    final rows = await _db
        .customSelect(
          kHardestCardsSql,
          variables: [
            Variable.withInt(kHardestCardsMinReviews),
            Variable.withInt(kHardestCardsLimit),
          ],
          readsFrom: reviewHistoryTables(_db).toSet(),
        )
        .get();

    return [
      for (final row in rows)
        DifficultCard(
          flashcardId: row.read<String>('flashcard_id'),
          front: row.read<String>('front'),
          total: row.read<int>('total'),
          againCount: row.read<int>('again_count'),
        ),
    ];
  }

  @override
  Stream<ReviewHistory> watch() {
    return watchQuery(
      db: _db,
      tables: reviewHistoryTables(_db),
      read: current,
      telemetry: _telemetry,
      hint: 'ReviewHistoryRepositoryImpl.watch',
    );
  }
}
