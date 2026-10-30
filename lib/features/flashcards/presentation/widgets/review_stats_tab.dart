import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/domain/services/review_stats_math.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_palette.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/stats_charts.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pestaña «Estadísticas» (F43, M17), de lo de hoy a lo de siempre: hoy,
/// lo que viene, los repasos por día, cómo están las tarjetas, cómo se
/// responde, los intervalos, la facilidad, las horas y lo agregado.
///
/// Los tramos que se eligen en cada gráfico son cortes de [stats], que ya
/// trae todo: cambiar uno no vuelve a leer la base ni parpadea la pantalla.
class ReviewStatsSections extends ConsumerStatefulWidget {
  const ReviewStatsSections({required this.stats, super.key});

  final ReviewStats stats;

  @override
  ConsumerState<ReviewStatsSections> createState() =>
      _ReviewStatsSectionsState();
}

class _ReviewStatsSectionsState extends ConsumerState<ReviewStatsSections> {
  var _forecast = ForecastRange.days30;
  var _daily = StatsPeriod.days30;
  var _buttons = StatsPeriod.days30;
  var _added = StatsPeriod.days30;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final now = ref.watch(clockProvider)();
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodaySection(today: stats.today),
        gap,
        _ForecastSection(
          forecast: stats.forecast.window(_forecast),
          range: _forecast,
          onRange: (r) => setState(() => _forecast = r),
        ),
        gap,
        _DailySection(
          daily: stats.daily,
          period: _daily,
          now: now,
          onPeriod: (p) => setState(() => _daily = p),
        ),
        gap,
        _DistributionSection(distribution: stats.distribution),
        gap,
        _ButtonsSection(
          usage: stats.buttonsFor(_buttons),
          period: _buttons,
          onPeriod: (p) => setState(() => _buttons = p),
        ),
        gap,
        _IntervalsSection(intervals: stats.intervals),
        gap,
        _EaseSection(stats: stats),
        gap,
        _HoursSection(stats: stats),
        gap,
        _AddedSection(
          added: stats.added,
          period: _added,
          now: now,
          onPeriod: (p) => setState(() => _added = p),
        ),
      ],
    );
  }
}

/// Un número con un decimal a lo sumo, como se escribe en el idioma.
String _decimal(BuildContext context, double value) => NumberFormat(
  '#,##0.#',
  Localizations.localeOf(context).toString(),
).format(value);

String _percent(double ratio) => '${(ratio * 100).round()} %';

String _periodLabel(AppLocalizations l10n, StatsPeriod p) => switch (p) {
  StatsPeriod.days30 => l10n.cardStatsPeriod30,
  StatsPeriod.days90 => l10n.cardStatsPeriod90,
  StatsPeriod.all => l10n.cardStatsPeriodAll,
};

/// Una línea tenue: lo que dice un gráfico vacío, o un resumen debajo.
class _Muted extends StatelessWidget {
  const _Muted(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// La fecha de una barra de una serie por días: el día, o «semana del…».
String _barDate(BuildContext context, SeriesBar bar) {
  final l10n = AppLocalizations.of(context)!;
  final date = DateFormat.MMMd(
    Localizations.localeOf(context).toString(),
  ).format(bar.start);
  return bar.days == 1 ? date : l10n.f43S20WeekOf(date);
}

/// Los rótulos de abajo de una serie por días: la primera, la del medio y la
/// última.
Map<int, String> _seriesLabels(BuildContext context, List<SeriesBar> bars) {
  if (bars.isEmpty) return const {};
  final format = DateFormat.MMMd(Localizations.localeOf(context).toString());
  return {
    for (final i in {0, bars.length ~/ 2, bars.length - 1})
      i: format.format(bars[i].start),
  };
}

// ── 1. Hoy ──────────────────────────────────────────────────────────────

class _TodaySection extends ConsumerWidget {
  const _TodaySection({required this.today});

  final TodayStats today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final streak = ref.watch(currentStreakProvider).valueOrNull;
    final accuracy = today.accuracy;
    final tiles = [
      (
        'reviewed',
        '${today.cards}',
        l10n.f43S20TodayReviewed,
        l10n.f43S20TodayAnswers(today.answers),
      ),
      (
        'accuracy',
        accuracy == null ? '—' : _percent(accuracy),
        l10n.f43S20TodayAccuracy,
        accuracy == null
            ? l10n.cardStatsButtonsNoData
            : l10n.f43S20TodayCorrect(today.correct, today.answers),
      ),
      (
        'new',
        '${today.newCards}',
        l10n.f43S20TodayNew,
        l10n.f43S20TodayNewCaption,
      ),
      (
        'streak',
        '${streak?.days ?? 0}',
        l10n.f43S20TodayStreak,
        l10n.f43S20TodayStreakCaption(streak?.days ?? 0),
      ),
    ];
    return StatsSection(
      key: const Key('stats-today'),
      title: l10n.f43S20TodayTitle,
      subtitle: l10n.f43S20TodaySubtitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 560 ? 4 : 2;
          const spacing = 12.0;
          // Por filas, y cada fila con el alto de su cifra más alta: las
          // cuatro quedan parejas aunque una diga más que otra.
          return Column(
            children: [
              for (var start = 0; start < tiles.length; start += columns) ...[
                if (start > 0) const SizedBox(height: spacing),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start; i < start + columns; i++) ...[
                        if (i > start) const SizedBox(width: spacing),
                        Expanded(
                          child: _BigFigure(
                            key: Key('stats-today-${tiles[i].$1}'),
                            value: tiles[i].$2,
                            label: tiles[i].$3,
                            caption: tiles[i].$4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BigFigure extends StatelessWidget {
  const _BigFigure({
    required this.value,
    required this.label,
    required this.caption,
    super.key,
  });

  final String value;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                caption,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 2. Lo que viene ─────────────────────────────────────────────────────

class _ForecastSection extends StatelessWidget {
  const _ForecastSection({
    required this.forecast,
    required this.range,
    required this.onRange,
  });

  final ReviewForecast forecast;
  final ForecastRange range;
  final ValueChanged<ForecastRange> onRange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final date = DateFormat.MMMEd(Localizations.localeOf(context).toString());
    final summary = [
      l10n.cardStatsForecastToday(forecast.today),
      if (forecast.overdue > 0) l10n.cardStatsForecastOverdue(forecast.overdue),
    ].join(' · ');
    final bars = [
      for (final day in forecast.days)
        StatsBar(
          values: [day.count.toDouble()],
          description: l10n.cardStatsForecastBar(
            date.format(day.start),
            day.count,
          ),
        ),
    ];
    final last = forecast.days.length - 1;
    return StatsSection(
      key: const Key('stats-forecast'),
      title: l10n.cardStatsForecastTitle,
      subtitle: l10n.f43S20ForecastSubtitle,
      controls: StatsRangeChips<ForecastRange>(
        keyPrefix: 'stats-forecast-range',
        values: ForecastRange.values,
        selected: range,
        labelOf: (r) => switch (r) {
          ForecastRange.days7 => l10n.f43S20Range7,
          ForecastRange.days30 => l10n.cardStatsPeriod30,
          ForecastRange.months3 => l10n.f43S20Range3Months,
        },
        onSelected: onRange,
      ),
      table: [
        for (final day in forecast.days)
          if (day.count > 0) (date.format(day.start), '${day.count}'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            key: const Key('card-stats-forecast-today'),
            style: theme.textTheme.titleSmall,
          ),
          Text(
            l10n.f43S20ForecastAverage(
              _decimal(context, forecast.averagePerDay),
              forecast.total,
            ),
            key: const Key('stats-forecast-average'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (forecast.total == 0)
            _Muted(
              l10n.f43S20ForecastEmpty,
              key: const Key('card-stats-forecast-empty'),
            )
          else
            StatsBarChart(
              key: const Key('card-stats-forecast-chart'),
              bars: bars,
              colors: [theme.colorScheme.primary],
              semanticsLabel: l10n.f43S20ForecastChartLabel(
                forecast.days.length,
                forecast.total,
                forecast.peak,
              ),
              valueText: (bar) => '${bar.total.round()}',
              xLabels: {
                0: l10n.cardStatsForecastAxisToday,
                last ~/ 2: l10n.cardStatsForecastAxisDays(last ~/ 2),
                last: l10n.cardStatsForecastAxisDays(last),
              },
            ),
        ],
      ),
    );
  }
}

// ── 3. Repasos por día ──────────────────────────────────────────────────

class _DailySection extends StatelessWidget {
  const _DailySection({
    required this.daily,
    required this.period,
    required this.now,
    required this.onPeriod,
  });

  final List<DayReviews> daily;
  final StatsPeriod period;
  final DateTime now;
  final ValueChanged<StatsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = CardStatsPalette.of(context);
    final byDay = {for (final d in daily) d.day: d.byKind};
    final series = daySeries(
      period: period,
      now: now,
      first: daily.isEmpty ? null : daily.first.day,
      width: DailyReviewKind.values.length,
      valuesOf: (day) => byDay[day],
    );
    final total = series.fold(0, (sum, bar) => sum + bar.total);
    final days = series.fold(0, (sum, bar) => sum + bar.days);
    final kinds = [
      (palette.newCards, l10n.f43S20KindNew),
      (palette.learning, l10n.f43S20KindLearning),
      (palette.young, l10n.f43S20KindReview),
      (palette.mature, l10n.f43S20KindRelearning),
    ];
    String describe(SeriesBar bar) => l10n.f43S20DailyBar(
      _barDate(context, bar),
      bar.total,
      bar.values[DailyReviewKind.newCard.index],
      bar.values[DailyReviewKind.learning.index],
      bar.values[DailyReviewKind.review.index],
      bar.values[DailyReviewKind.relearning.index],
    );
    return StatsSection(
      key: const Key('stats-daily'),
      title: l10n.f43S20DailyTitle,
      subtitle: l10n.f43S20DailySubtitle,
      controls: StatsRangeChips<StatsPeriod>(
        keyPrefix: 'stats-daily-period',
        values: StatsPeriod.values,
        selected: period,
        labelOf: (p) => _periodLabel(l10n, p),
        onSelected: onPeriod,
      ),
      table: [
        for (final bar in series.reversed)
          if (bar.total > 0) (_barDate(context, bar), '${bar.total}'),
      ],
      child: total == 0
          ? _Muted(l10n.f43S20DailyEmpty, key: const Key('stats-daily-empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.f43S20DailySummary(
                    total,
                    _decimal(context, days == 0 ? 0 : total / days),
                  ),
                  key: const Key('stats-daily-summary'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                StatsBarChart(
                  key: const Key('stats-daily-chart'),
                  bars: [
                    for (final bar in series)
                      StatsBar(
                        values: [for (final v in bar.values) v.toDouble()],
                        description: describe(bar),
                      ),
                  ],
                  colors: [for (final (color, _) in kinds) color],
                  semanticsLabel: l10n.f43S20DailyChartLabel(
                    series.length,
                    total,
                  ),
                  xLabels: _seriesLabels(context, series),
                ),
                const SizedBox(height: 8),
                StatsLegend(entries: kinds),
              ],
            ),
    );
  }
}

// ── 4. Cómo están tus tarjetas ──────────────────────────────────────────

class _DistributionSection extends StatelessWidget {
  const _DistributionSection({required this.distribution});

  final CardDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = CardStatsPalette.of(context);
    final total = distribution.total;
    final parts = [
      ('new', l10n.cardStatsStageNew, distribution.newCards, palette.newCards),
      (
        'learning',
        l10n.cardStatsStageLearning,
        distribution.learning,
        palette.learning,
      ),
      ('young', l10n.cardStatsStageYoung, distribution.young, palette.young),
      (
        'mature',
        l10n.cardStatsStageMature,
        distribution.mature,
        palette.mature,
      ),
      (
        'suspended',
        l10n.cardStatsStageSuspended,
        distribution.suspended,
        palette.suspended,
      ),
    ];
    int percentOf(int count) => total == 0 ? 0 : (count * 100 / total).round();

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (key, label, count, color) in parts)
          Semantics(
            key: Key('card-stats-distribution-$key'),
            label: l10n.cardStatsDistributionRow(
              label,
              count,
              percentOf(count),
            ),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  const SizedBox(width: 8),
                  Text(
                    '$count · ${percentOf(count)} %',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return StatsSection(
      key: const Key('stats-distribution'),
      title: l10n.cardStatsDistributionTitle,
      subtitle: l10n.f43S20DistributionSubtitle,
      child: total == 0
          ? _Muted(
              l10n.cardStatsDistributionEmpty,
              key: const Key('card-stats-distribution-empty'),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final donut = Semantics(
                  label: l10n.cardStatsDistributionTotal(total),
                  excludeSemantics: true,
                  child: StatsDonut(
                    key: const Key('stats-distribution-donut'),
                    values: [for (final (_, _, count, _) in parts) count],
                    colors: [for (final (_, _, _, color) in parts) color],
                    center: '$total',
                    centerCaption: l10n.f43S20DistributionCenter(total),
                  ),
                );
                // Al lado si hay ancho; si no, debajo.
                if (constraints.maxWidth >= 480) {
                  return Row(
                    children: [
                      donut,
                      const SizedBox(width: 24),
                      Expanded(child: list),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: donut),
                    const SizedBox(height: 12),
                    list,
                  ],
                );
              },
            ),
    );
  }
}

// ── 5. Cómo respondés ───────────────────────────────────────────────────

class _ButtonsSection extends StatelessWidget {
  const _ButtonsSection({
    required this.usage,
    required this.period,
    required this.onPeriod,
  });

  final ButtonUsageByStage usage;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stages = <(String, String, ButtonUsage)>[
      ('overall', l10n.cardStatsButtonsOverall, usage.overall),
      for (final stage in StatsStage.values)
        (
          stage.name,
          switch (stage) {
            StatsStage.newCard => l10n.cardStatsStageNew,
            StatsStage.learning => l10n.cardStatsStageLearning,
            StatsStage.young => l10n.cardStatsStageYoung,
            StatsStage.mature => l10n.cardStatsStageMature,
          },
          usage.of(stage),
        ),
    ];
    return StatsSection(
      key: const Key('stats-buttons'),
      title: l10n.cardStatsButtonsTitle,
      subtitle: l10n.cardStatsButtonsSubtitle,
      controls: StatsRangeChips<StatsPeriod>(
        keyPrefix: 'card-stats-period',
        values: StatsPeriod.values,
        selected: period,
        labelOf: (p) => _periodLabel(l10n, p),
        onSelected: onPeriod,
      ),
      child: usage.overall.total == 0
          ? _Muted(
              l10n.cardStatsButtonsEmpty,
              key: const Key('card-stats-buttons-empty'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (key, label, stageUsage) in stages)
                  _StageRow(keyName: key, label: label, usage: stageUsage),
              ],
            ),
    );
  }
}

/// Una etapa: su acierto, la barra apilada de los cuatro botones y, debajo,
/// cada botón con su número y su porcentaje.
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.keyName,
    required this.label,
    required this.usage,
  });

  final String keyName;
  final String label;
  final ButtonUsage usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = CardStatsPalette.of(context);
    final accuracy = usage.accuracy;
    final grades = [
      ('again', l10n.reviewGradeAgain, usage.again, palette.again),
      ('hard', l10n.reviewGradeHard, usage.hard, palette.hard),
      ('good', l10n.reviewGradeGood, usage.good, palette.good),
      ('easy', l10n.reviewGradeEasy, usage.easy, palette.easy),
    ];
    String share(int count) =>
        usage.total == 0 ? '0 %' : _percent(count / usage.total);

    return Padding(
      key: Key('card-stats-buttons-row-$keyName'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        label: accuracy == null
            ? l10n.cardStatsButtonsRowEmpty(label)
            : l10n.cardStatsButtonsRowLabel(
                label,
                usage.again,
                usage.hard,
                usage.good,
                usage.easy,
                (accuracy * 100).round(),
              ),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            Text(
              accuracy == null
                  ? l10n.cardStatsButtonsNoData
                  : l10n.cardStatsButtonsAccuracy(
                      (accuracy * 100).round(),
                      usage.total,
                    ),
              key: Key('card-stats-buttons-accuracy-$keyName'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 14,
              child: usage.total == 0
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )
                  : Row(
                      children: [
                        for (final (gradeKey, _, count, color) in grades)
                          if (count > 0)
                            Expanded(
                              flex: count,
                              child: Padding(
                                // Los 2 px de aire entre tramos.
                                padding: const EdgeInsets.only(right: 2),
                                child: DecoratedBox(
                                  key: Key(
                                    'card-stats-buttons-segment-$keyName-'
                                    '$gradeKey',
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
            const SizedBox(height: 6),
            StatsLegend(
              entries: [
                for (final (_, gradeLabel, count, color) in grades)
                  (color, '$gradeLabel $count · ${share(count)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 6. Intervalos ───────────────────────────────────────────────────────

class _IntervalsSection extends StatelessWidget {
  const _IntervalsSection({required this.intervals});

  final Map<IntervalRange, int> intervals;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    String rangeLabel(IntervalRange r) => switch (r) {
      IntervalRange.oneDay => l10n.f43S20IntervalOneDay,
      IntervalRange.longer => l10n.f43S20IntervalLonger(r.from - 1),
      _ => l10n.f43S20IntervalRange(r.from, r.to!),
    };
    final total = intervals.values.fold(0, (sum, n) => sum + n);
    return StatsSection(
      key: const Key('stats-intervals'),
      title: l10n.f43S20IntervalsTitle,
      subtitle: l10n.f43S20IntervalsSubtitle,
      table: [
        for (final r in IntervalRange.values)
          (rangeLabel(r), '${intervals[r] ?? 0}'),
      ],
      child: total == 0
          ? _Muted(
              l10n.f43S20NoReviewCards,
              key: const Key('stats-intervals-empty'),
            )
          : StatsBarChart(
              key: const Key('stats-intervals-chart'),
              bars: [
                for (final r in IntervalRange.values)
                  StatsBar(
                    values: [(intervals[r] ?? 0).toDouble()],
                    description: l10n.f43S20CardsIn(
                      rangeLabel(r),
                      intervals[r] ?? 0,
                    ),
                  ),
              ],
              colors: [theme.colorScheme.primary],
              semanticsLabel: l10n.f43S20IntervalsChartLabel(total),
              valueText: (bar) => '${bar.total.round()}',
              xLabels: {
                for (final r in IntervalRange.values)
                  r.index: switch (r) {
                    IntervalRange.oneDay => l10n.f43S20AxisDays('1'),
                    IntervalRange.longer => '+${r.from - 1}',
                    _ => l10n.f43S20AxisDays('${r.from}–${r.to}'),
                  },
              },
            ),
    );
  }
}

// ── 7. Facilidad ────────────────────────────────────────────────────────

class _EaseSection extends StatelessWidget {
  const _EaseSection({required this.stats});

  final ReviewStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bands = easeBands(stats.ease);
    final average = stats.averageEase;
    String bandLabel(EaseBand b) => b.to == null
        ? l10n.f43S20EaseFrom(b.from)
        : l10n.f43S20EaseBand(b.from, b.to!);
    return StatsSection(
      key: const Key('stats-ease'),
      title: l10n.f43S20EaseTitle,
      subtitle: l10n.f43S20EaseSubtitle,
      table: [for (final b in bands) (bandLabel(b), '${b.count}')],
      child: average == null
          ? _Muted(l10n.f43S20NoReviewCards, key: const Key('stats-ease-empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.f43S20EaseAverage(average.round()),
                  key: const Key('stats-ease-average'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                StatsBarChart(
                  key: const Key('stats-ease-chart'),
                  bars: [
                    for (final b in bands)
                      StatsBar(
                        values: [b.count.toDouble()],
                        description: l10n.f43S20CardsIn(bandLabel(b), b.count),
                      ),
                  ],
                  colors: [theme.colorScheme.primary],
                  semanticsLabel: l10n.f43S20EaseChartLabel(average.round()),
                  valueText: (bar) => '${bar.total.round()}',
                  xLabels: {
                    for (final (i, b) in bands.indexed)
                      i: b.to == null ? '${b.from}+' : '${b.from}',
                  },
                ),
              ],
            ),
    );
  }
}

// ── 8. Las horas ────────────────────────────────────────────────────────

class _HoursSection extends StatelessWidget {
  const _HoursSection({required this.stats});

  final ReviewStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = stats.bestHour;
    final answers = stats.hours.fold(0, (sum, h) => sum + h.answers);
    String hourRange(int h) => l10n.f43S20HourRange(h, (h + 1) % 24);
    String describe(HourAccuracy h) => h.accuracy == null
        ? l10n.f43S20HourEmpty(hourRange(h.hour))
        : l10n.f43S20HourBar(
            hourRange(h.hour),
            (h.accuracy! * 100).round(),
            h.answers,
          );
    // Con pocas respuestas, un 100 % no dice mucho: esas horas van en un
    // tono más tenue, con su rótulo en la leyenda.
    final firm = scheme.primary;
    final few = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.4),
      scheme.surfaceContainerLow,
    );
    return StatsSection(
      key: const Key('stats-hours'),
      title: l10n.f43S20HoursTitle,
      subtitle: l10n.f43S20HoursSubtitle,
      table: [
        for (final h in stats.hours)
          if (h.answers > 0)
            (
              hourRange(h.hour),
              l10n.f43S20HourCell((h.accuracy! * 100).round(), h.answers),
            ),
      ],
      child: answers == 0
          ? _Muted(l10n.f43S20NoAnswers, key: const Key('stats-hours-empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  best == null
                      ? l10n.f43S20BestHourNone(kBestHourMinAnswers)
                      : l10n.f43S20BestHour(
                          hourRange(best.hour),
                          (best.accuracy! * 100).round(),
                        ),
                  key: const Key('stats-best-hour'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                StatsBarChart(
                  key: const Key('stats-hours-chart'),
                  bars: [
                    for (final h in stats.hours)
                      StatsBar(
                        values: h.answers >= kBestHourMinAnswers
                            ? [h.accuracy! * 100, 0]
                            : [0, (h.accuracy ?? 0) * 100],
                        description: describe(h),
                      ),
                  ],
                  colors: [firm, few],
                  maxValue: 100,
                  tickText: (v) => '${v.round()} %',
                  semanticsLabel: l10n.f43S20HoursChartLabel(answers),
                  xLabels: const {0: '0 h', 6: '6 h', 12: '12 h', 18: '18 h'},
                ),
                const SizedBox(height: 8),
                StatsLegend(
                  entries: [
                    (firm, l10n.f43S20HoursFirm(kBestHourMinAnswers)),
                    (few, l10n.f43S20HoursFew(kBestHourMinAnswers)),
                  ],
                ),
              ],
            ),
    );
  }
}

// ── 9. Agregadas ────────────────────────────────────────────────────────

class _AddedSection extends StatelessWidget {
  const _AddedSection({
    required this.added,
    required this.period,
    required this.now,
    required this.onPeriod,
  });

  final List<DayCount> added;
  final StatsPeriod period;
  final DateTime now;
  final ValueChanged<StatsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final byDay = {for (final d in added) d.day: d.count};
    final series = daySeries(
      period: period,
      now: now,
      first: added.isEmpty ? null : added.first.day,
      width: 1,
      valuesOf: (day) => byDay[day] == null ? null : [byDay[day]!],
    );
    final total = series.fold(0, (sum, bar) => sum + bar.total);
    final days = series.fold(0, (sum, bar) => sum + bar.days);
    return StatsSection(
      key: const Key('stats-added'),
      title: l10n.f43S20AddedTitle,
      subtitle: l10n.f43S20AddedSubtitle,
      controls: StatsRangeChips<StatsPeriod>(
        keyPrefix: 'stats-added-period',
        values: StatsPeriod.values,
        selected: period,
        labelOf: (p) => _periodLabel(l10n, p),
        onSelected: onPeriod,
      ),
      table: [
        for (final bar in series.reversed)
          if (bar.total > 0) (_barDate(context, bar), '${bar.total}'),
      ],
      child: total == 0
          ? _Muted(l10n.f43S20AddedEmpty, key: const Key('stats-added-empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.f43S20AddedSummary(
                    total,
                    _decimal(context, days == 0 ? 0 : total / days),
                  ),
                  key: const Key('stats-added-summary'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                StatsBarChart(
                  key: const Key('stats-added-chart'),
                  bars: [
                    for (final bar in series)
                      StatsBar(
                        values: [bar.total.toDouble()],
                        description: l10n.f43S20AddedBar(
                          _barDate(context, bar),
                          bar.total,
                        ),
                      ),
                  ],
                  colors: [theme.colorScheme.primary],
                  semanticsLabel: l10n.f43S20AddedChartLabel(
                    series.length,
                    total,
                  ),
                  xLabels: _seriesLabels(context, series),
                ),
              ],
            ),
    );
  }
}
