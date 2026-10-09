import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_sql.dart';
import 'package:sinapsis/features/flashcards/domain/entities/card_browser_query.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/card_browser_repository.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/review_stats_repository.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';

/// [ReviewStatsRepository] sobre la base (F31, ola 2, decisión 72).
///
/// El reparto por etapa NO se calcula acá: lo pide a [CardBrowserRepository]
/// (`statusCounts`), el mismo que rotula los filtros de «Mis tarjetas». Hay una
/// sola respuesta a «cuántas son maduras», y los dos números no pueden
/// discrepar.
class ReviewStatsRepositoryImpl implements ReviewStatsRepository {
  const ReviewStatsRepositoryImpl({
    required AppDatabase database,
    required TelemetryService telemetry,
    required Clock clock,
    required CardBrowserRepository browser,
    StudyDay day = const StudyDay(),
  }) : _db = database,
       _telemetry = telemetry,
       _clock = clock,
       _browser = browser,
       _day = day;

  final AppDatabase _db;
  final TelemetryService _telemetry;
  final Clock _clock;
  final CardBrowserRepository _browser;
  final StudyDay _day;

  @override
  Future<Either<Failure, ReviewStats>> load({
    required StatsPeriod period,
  }) async {
    try {
      final now = _clock();
      final distribution = await _distribution();
      return await distribution.match(
        (failure) async => left(failure),
        (distribution) async => right(
          ReviewStats(
            forecast: await _forecast(now),
            distribution: distribution,
            buttons: await _buttons(now, period),
            period: period,
          ),
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
  Stream<ReviewStats> watch({required StatsPeriod period}) => watchQuery(
    db: _db,
    tables: [_db.flashcards, _db.reviewLogs, _db.knowledgeEntries],
    read: () async {
      final result = await load(period: period);
      // Un fallo viaja por el stream, como en el resto de las lecturas.
      return result.getOrElse((failure) => throw StateError('$failure'));
    },
    telemetry: _telemetry,
    hint: 'ReviewStatsRepositoryImpl.watch',
  );

  Future<Either<Failure, CardDistribution>> _distribution() async {
    final counts = await _browser.statusCounts(const CardBrowserQuery());
    return counts.map(
      (c) => CardDistribution(
        newCards: c[CardBrowserStatus.newCards] ?? 0,
        learning: c[CardBrowserStatus.learning] ?? 0,
        young: c[CardBrowserStatus.young] ?? 0,
        mature: c[CardBrowserStatus.mature] ?? 0,
        suspended: c[CardBrowserStatus.suspended] ?? 0,
      ),
    );
  }

  /// Cuántas vencen en cada uno de los próximos [kForecastDays] días de
  /// estudio.
  ///
  /// Cuenta lo programado —no lo nuevo, que no tiene fecha— y no pausado. Una
  /// tarjeta pospuesta cuenta el día en que vuelve, no el que tenía. Los bordes
  /// de cada día son `DateTime(año, mes, día, 4)` en la zona de ahora, no sumas
  /// de 24 horas: el día del cambio de horario mide 23 o 25.
  Future<ReviewForecast> _forecast(DateTime now) async {
    final today = _day.startOf(now);
    // Los bordes: el principio de hoy, y el fin de cada día del pronóstico.
    DateTime edge(int days) =>
        DateTime(today.year, today.month, today.day + days, _day.startHour);
    final ends = [for (var k = 1; k <= kForecastDays; k++) edge(k)];

    final whens = [
      'WHEN eff < ? THEN -1',
      for (var k = 0; k < kForecastDays; k++) 'WHEN eff < ? THEN $k',
    ].join(' ');
    final rows = await _db
        .customSelect(
          'SELECT CASE $whens END AS bucket, COUNT(*) AS n FROM ( '
          'SELECT CASE WHEN f.buried_until IS NOT NULL '
          'AND f.buried_until > ? AND f.buried_until > f.due_at '
          'THEN f.buried_until ELSE f.due_at END AS eff '
          '${CardBrowserSql.from} '
          'WHERE i.deleted_at IS NULL AND f.suspended = 0 '
          'AND NOT (${CardBrowserSql.isNew}) '
          ') WHERE eff < ? GROUP BY bucket',
          variables: [
            Variable.withDateTime(today),
            for (final end in ends) Variable.withDateTime(end),
            Variable.withDateTime(now),
            Variable.withDateTime(ends.last),
          ],
          readsFrom: {_db.flashcards, _db.knowledgeEntries},
        )
        .get();

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

  /// Cuántas veces se apretó cada botón en cada etapa, con el historial de
  /// [period]. La etapa es la que tenía la tarjeta ANTES de contestarla
  /// (`phase_before`); un repaso se reparte entre joven y maduro por el
  /// intervalo de antes.
  Future<ButtonUsageByStage> _buttons(DateTime now, StatsPeriod period) async {
    final days = period.days;
    final since = days == null
        ? null
        : () {
            final today = _day.startOf(now);
            return DateTime(
              today.year,
              today.month,
              today.day - (days - 1),
              _day.startHour,
            );
          }();

    final rows = await _db
        .customSelect(
          'SELECT CASE '
          "WHEN rl.phase_before = 'newCard' THEN 'new' "
          "WHEN rl.phase_before IN ('learning', 'relearning') THEN 'learning' "
          "WHEN rl.interval_before < $kMatureIntervalDays THEN 'young' "
          "ELSE 'mature' END AS stage, rl.grade AS grade, COUNT(*) AS n "
          'FROM review_log rl JOIN flashcards f ON f.id = rl.flashcard_id '
          'JOIN item i ON i.id = f.item_id '
          'WHERE i.deleted_at IS NULL '
          '${since == null ? '' : 'AND rl.reviewed_at >= ? '}'
          'GROUP BY stage, grade',
          variables: [if (since != null) Variable.withDateTime(since)],
          readsFrom: {_db.reviewLogs, _db.flashcards, _db.knowledgeEntries},
        )
        .get();

    final tally = <StatsStage, List<int>>{}; // again, hard, good, easy
    for (final row in rows) {
      final stage = switch (row.read<String>('stage')) {
        'new' => StatsStage.newCard,
        'learning' => StatsStage.learning,
        'young' => StatsStage.young,
        _ => StatsStage.mature,
      };
      final slot = switch (row.read<String>('grade')) {
        'again' => 0,
        'hard' => 1,
        'good' => 2,
        'easy' => 3,
        _ => -1,
      };
      if (slot < 0) continue;
      (tally[stage] ??= [0, 0, 0, 0])[slot] += row.read<int>('n');
    }
    return ButtonUsageByStage({
      for (final entry in tally.entries)
        entry.key: ButtonUsage(
          again: entry.value[0],
          hard: entry.value[1],
          good: entry.value[2],
          easy: entry.value[3],
        ),
    });
  }
}
