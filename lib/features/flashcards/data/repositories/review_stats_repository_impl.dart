import 'package:drift/drift.dart' show Variable;
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_sql.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_reader.dart';
import 'package:sinapsis/features/flashcards/data/repositories/review_scope_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/review_stats_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/review_stats_math.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_scope_resolver.dart';

/// [ReviewStatsRepository] sobre la base (F43, M17; F31, decisión 72).
///
/// El recorte se resuelve una vez y cada número sale de una consulta en lote
/// (`ReviewScopeSql`): el reparto, el pronóstico, las respuestas agrupadas, lo
/// de hoy, la forma de las tarjetas y lo agregado. Seis lecturas, tenga el
/// recorte diez tarjetas o diez mil.
///
/// El reparto por etapa usa el mismo SQL que rotula los filtros de «Mis
/// tarjetas» (`CardBrowserSql.statusCountsSql`): hay una sola respuesta a
/// «cuántas son maduras», y los dos números no pueden discrepar.
class ReviewStatsRepositoryImpl implements ReviewStatsRepository {
  ReviewStatsRepositoryImpl({
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
  Future<Either<Failure, ReviewStats>> load({required StudyScope scope}) async {
    try {
      final now = _clock();
      final sql = await _reader.sqlFor(scope);
      final activity = await _reader.activity(sql);
      final shape = await _cardShape(sql);
      return right(
        ReviewStats(
          today: await _today(sql, now),
          forecast: await _forecast(sql, now),
          daily: dailyReviews(activity, day: _day),
          distribution: await _distribution(sql, now),
          buttons: buttonsByPeriod(activity, now: now, day: _day),
          intervals: shape.intervals,
          ease: shape.ease,
          hours: hourAccuracy(activity),
          added: await _added(sql),
        ),
      );
      // Catch-all deliberado, igual que en el resto de los repositorios: un
      // TypeError es Error, no Exception.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ReviewStatsRepositoryImpl.load',
      );
      return left(Failure.unexpected(message: e.toString()));
    }
  }

  @override
  Stream<ReviewStats> watch({required StudyScope scope}) => watchQuery(
    db: _db,
    tables: _reader.watched,
    read: () async {
      final result = await load(scope: scope);
      // Un fallo viaja por el stream, como en el resto de las lecturas.
      return result.getOrElse((failure) => throw StateError('$failure'));
    },
    telemetry: _telemetry,
    hint: 'ReviewStatsRepositoryImpl.watch',
  );

  Future<CardDistribution> _distribution(
    ReviewScopeSql sql,
    DateTime now,
  ) async {
    final rows = await _reader.rows((
      sql: CardBrowserSql.statusCountsSql(sql.where),
      variables: [
        Variable.withDateTime(_day.endOf(now)),
        Variable.withDateTime(now),
        ...sql.args,
      ],
    ));
    final c = CardBrowserSql.statusCountsOf(rows.single);
    return CardDistribution(
      newCards: c[CardBrowserStatus.newCards]!,
      learning: c[CardBrowserStatus.learning]!,
      young: c[CardBrowserStatus.young]!,
      mature: c[CardBrowserStatus.mature]!,
      suspended: c[CardBrowserStatus.suspended]!,
    );
  }

  Future<TodayStats> _today(ReviewScopeSql sql, DateTime now) async {
    final row = (await _reader.rows(sql.today(_day.startOf(now)))).single;
    return TodayStats(
      cards: row.read<int>('cards'),
      answers: row.read<int>('answers'),
      correct: row.read<int>('correct'),
      newCards: row.read<int>('new_cards'),
    );
  }

  /// Cuántas vencen en cada uno de los próximos [kForecastDays] días de
  /// estudio. Los bordes de cada día son `DateTime(año, mes, día, 4)` en la
  /// zona de ahora, no sumas de 24 horas: el día del cambio de horario mide 23
  /// o 25.
  Future<ReviewForecast> _forecast(ReviewScopeSql sql, DateTime now) async {
    final today = _day.startOf(now);
    DateTime edge(int days) =>
        DateTime(today.year, today.month, today.day + days, _day.startHour);
    final rows = await _reader.rows(
      sql.forecast(
        today: today,
        now: now,
        ends: [for (var k = 1; k <= kForecastDays; k++) edge(k)],
      ),
    );
    final perBucket = {
      for (final row in rows) row.read<int>('bucket'): row.read<int>('n'),
    };
    final overdue = perBucket[-1] ?? 0;
    return ReviewForecast(
      overdue: overdue,
      days: [
        for (var k = 0; k < kForecastDays; k++)
          ForecastDay(
            start: edge(k),
            count: (perBucket[k] ?? 0) + (k == 0 ? overdue : 0),
          ),
      ],
    );
  }

  Future<({Map<IntervalRange, int> intervals, List<EaseCount> ease})>
  _cardShape(ReviewScopeSql sql) async {
    final intervals = {for (final range in IntervalRange.values) range: 0};
    final ease = <int, int>{};
    for (final row in await _reader.rows(sql.cardShape)) {
      final n = row.read<int>('n');
      final range = IntervalRange.values[row.read<int>('band')];
      intervals[range] = intervals[range]! + n;
      final percent = row.read<int>('ease');
      ease[percent] = (ease[percent] ?? 0) + n;
    }
    final percents = ease.keys.toList()..sort();
    return (
      intervals: intervals,
      ease: [for (final p in percents) EaseCount(percent: p, count: ease[p]!)],
    );
  }

  Future<List<DayCount>> _added(ReviewScopeSql sql) async => addedPerDay([
    for (final row in await _reader.rows(sql.added))
      (
        start: ReviewScopeReader.quarterStart(row.read<int>('q')),
        count: row.read<int>('n'),
      ),
  ], day: _day);
}
