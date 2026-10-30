import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/stats_charts.dart';
import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/entities/true_retention.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';
import 'package:sinapsis/features/habit/domain/services/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/services/weekly_retention.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La pestaña «Historial» (F43, M16; F17, D8): la retención por semana con la
/// retención real debajo, la constancia con su calendario y las tarjetas que
/// de verdad cuestan, de lo más agregado a lo más puntual.
class ReviewHistorySections extends StatefulWidget {
  const ReviewHistorySections({required this.history, super.key});

  final ReviewHistory history;

  @override
  State<ReviewHistorySections> createState() => _ReviewHistorySectionsState();
}

class _ReviewHistorySectionsState extends State<ReviewHistorySections> {
  var _range = ActivityRange.months3;

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RetentionSection(weeks: history.retentionByWeek),
        gap,
        _TrueRetentionSection(rows: history.trueRetention),
        gap,
        _ActivitySection(
          history: history,
          range: _range,
          onRange: (r) => setState(() => _range = r),
        ),
        gap,
        _HardestSection(cards: history.hardestCards),
      ],
    );
  }
}

String _percentOf(double ratio) => '${(ratio * 100).round()} %';

class _Muted extends StatelessWidget {
  const _Muted(this.text);

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

// ── La retención por semana ─────────────────────────────────────────────

class _RetentionSection extends StatelessWidget {
  const _RetentionSection({required this.weeks});

  final List<WeeklyRetention> weeks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.MMMd(locale);
    String describe(WeeklyRetention w) => w.total == 0
        ? l10n.f43S20WeekNoReviews(date.format(w.weekStart))
        : l10n.f43S20WeekRetention(
            date.format(w.weekStart),
            (w.ratio * 100).round(),
            w.total,
          );
    final hasData = weeks.any((w) => w.total > 0);
    final last = weeks.length - 1;
    return StatsSection(
      key: const Key('review-history-retention'),
      title: l10n.reviewHistoryRetentionSectionTitle,
      subtitle: l10n.f43S20RetentionSubtitle,
      table: [
        for (final w in weeks.reversed)
          (
            l10n.f43S20WeekOf(date.format(w.weekStart)),
            w.total == 0
                ? l10n.cardStatsButtonsNoData
                : l10n.f43S20PercentOf(_percentOf(w.ratio), w.total),
          ),
      ],
      child: !hasData
          ? _Muted(l10n.reviewHistoryRetentionEmpty)
          : StatsBarChart(
              key: const Key('review-history-retention-chart'),
              bars: [
                for (final w in weeks)
                  StatsBar(
                    values: [if (w.total == 0) 0 else w.ratio * 100],
                    description: describe(w),
                  ),
              ],
              colors: [theme.colorScheme.primary],
              maxValue: 100,
              tickText: (v) => '${v.round()} %',
              valueText: (bar) => '${bar.total.round()}',
              reference: kRetentionTarget * 100,
              referenceLabel: l10n.f43S20RetentionTarget,
              semanticsLabel: l10n.f43S20RetentionChartLabel(weeks.length),
              xLabels: {
                for (final i in {0, last ~/ 2, last})
                  i: date.format(weeks[i].weekStart),
              },
            ),
    );
  }
}

// ── La retención real ───────────────────────────────────────────────────

class _TrueRetentionSection extends StatelessWidget {
  const _TrueRetentionSection({required this.rows});

  final List<TrueRetentionRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    String periodLabel(RetentionPeriod p) => switch (p) {
      RetentionPeriod.today => l10n.f43S20PeriodToday,
      RetentionPeriod.yesterday => l10n.f43S20PeriodYesterday,
      RetentionPeriod.week => l10n.f43S20PeriodWeek,
      RetentionPeriod.month => l10n.f43S20PeriodMonth,
      RetentionPeriod.year => l10n.f43S20PeriodYear,
    };
    String spoken(PassFail p) => p.ratio == null
        ? l10n.cardStatsButtonsNoData
        : l10n.f43S20PercentOf(_percentOf(p.ratio!), p.total);
    Widget cell(PassFail p, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            p.ratio == null ? '—' : _percentOf(p.ratio!),
            style:
                (strong
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
          Text(
            l10n.f43S20RetentionCount(p.total),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return StatsSection(
      key: const Key('review-history-true-retention'),
      title: l10n.f43S20TrueRetentionTitle,
      subtitle: l10n.f43S20TrueRetentionSubtitle,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.4),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(
          horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              header(l10n.f43S20Young),
              header(l10n.f43S20Mature),
              header(l10n.f43S20Total),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                Semantics(
                  key: ValueKey('true-retention-${row.period.name}'),
                  label: l10n.f43S20TrueRetentionRow(
                    periodLabel(row.period),
                    spoken(row.young),
                    spoken(row.mature),
                    spoken(row.total),
                  ),
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(periodLabel(row.period)),
                  ),
                ),
                ExcludeSemantics(child: cell(row.young)),
                ExcludeSemantics(child: cell(row.mature)),
                ExcludeSemantics(child: cell(row.total, strong: true)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── La constancia ───────────────────────────────────────────────────────

class _ActivitySection extends StatefulWidget {
  const _ActivitySection({
    required this.history,
    required this.range,
    required this.onRange,
  });

  final ReviewHistory history;
  final ActivityRange range;
  final ValueChanged<ActivityRange> onRange;

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final days = widget.history.activityByDay;
    final shown = days.sublist(math.max(0, days.length - widget.range.days));
    final summary = activitySummary(shown);
    final longDate = DateFormat.MMMEd(locale);
    String describe(DailyActivity d) => d.count == 0
        ? l10n.f43S20DayEmpty(longDate.format(d.day))
        : l10n.f43S20DayReviews(
            longDate.format(d.day),
            d.count,
            (d.accuracy! * 100).round(),
          );
    final selected = _selected == null
        ? null
        : shown.where((d) => d.day == _selected).firstOrNull;
    final figures = [
      (
        'current',
        l10n.f43S20RunCurrent,
        l10n.f43S20RunDays(widget.history.currentRun),
      ),
      (
        'longest',
        l10n.f43S20RunLongest,
        l10n.f43S20RunDays(widget.history.longestRun),
      ),
      (
        'studied',
        l10n.f43S20StudiedDays,
        l10n.f43S20StudiedOf(
          summary.studied,
          summary.days,
          summary.days == 0
              ? 0
              : (summary.studied * 100 / summary.days).round(),
        ),
      ),
      (
        'average',
        l10n.f43S20Average,
        l10n.f43S20AveragePerDay(
          NumberFormat('#,##0.#', locale).format(summary.average),
        ),
      ),
    ];

    return StatsSection(
      key: const Key('review-history-activity'),
      title: l10n.reviewHistoryActivitySectionTitle,
      subtitle: l10n.f43S20ActivitySubtitle,
      controls: StatsRangeChips<ActivityRange>(
        keyPrefix: 'review-history-range',
        values: ActivityRange.values,
        selected: widget.range,
        labelOf: (r) => switch (r) {
          ActivityRange.days30 => l10n.cardStatsPeriod30,
          ActivityRange.months3 => l10n.f43S20Range3Months,
          ActivityRange.year => l10n.f43S20RangeYear,
        },
        onSelected: (r) {
          setState(() => _selected = null);
          widget.onRange(r);
        },
      ),
      table: [
        for (final d in shown.reversed)
          if (d.count > 0)
            (
              longDate.format(d.day),
              l10n.f43S20DayCell(d.count, (d.accuracy! * 100).round()),
            ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final (key, label, value) in figures)
                MergeSemantics(
                  key: Key('review-history-$key'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(value, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            selected == null ? l10n.f43S20DayTapHint : describe(selected),
            key: const Key('review-history-day-callout'),
            style: selected == null
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
          ),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            label: l10n.f43S20ActivityChartLabel(summary.studied, summary.days),
            excludeSemantics: true,
            child: ActivityCalendar(
              key: const Key('review-history-activity-calendar'),
              days: shown,
              selected: _selected,
              onSelected: (day) => setState(() => _selected = day),
            ),
          ),
          const SizedBox(height: 8),
          _CalendarLegend(),
        ],
      ),
    );
  }
}

/// La intensidad de un día: 0 sin repasos, y de 1 a 4 según cuánto se acerca
/// al día con más del tramo.
int activityLevel(int count, int max) {
  if (count <= 0 || max <= 0) return 0;
  return (count * 4 / max).ceil().clamp(1, 4);
}

/// El color de cada nivel: un solo tono, de tenue a lleno (una escala
/// secuencial), y el vacío en la superficie más alta.
List<Color> activityColors(ColorScheme scheme) => [
  scheme.surfaceContainerHighest,
  for (final alpha in const [0.3, 0.52, 0.76, 1.0])
    Color.alphaBlend(
      scheme.primary.withValues(alpha: alpha),
      scheme.surfaceContainerLow,
    ),
];

class _CalendarLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = activityColors(theme.colorScheme);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(l10n.f43S20Less, style: style),
          const SizedBox(width: 6),
          for (final color in colors)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 6),
          Text(l10n.f43S20More, style: style),
        ],
      ),
    );
  }
}

/// El calendario de constancia: una columna por semana (de lunes a domingo),
/// los meses arriba y los días de la semana al costado. Tocar un día lo
/// elige.
///
/// Las celdas se agrandan hasta llenar el ancho, entre 12 y 28 puntos; con
/// un año entero no entran en un teléfono, y el calendario se desliza de
/// costado empezando por hoy.
class ActivityCalendar extends StatelessWidget {
  const ActivityCalendar({
    required this.days,
    required this.onSelected,
    this.selected,
    super.key,
  });

  /// Del más viejo al de hoy, uno por día de estudio.
  final List<DailyActivity> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final style = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final layout = CalendarLayout(days.map((d) => d.day).toList());
    final weekday = DateFormat.EEEEE(locale);
    final month = DateFormat.MMM(locale);
    // Los rótulos de los días: los siete, con la inicial del idioma.
    final weekdayLabels = [
      for (var i = 0; i < 7; i++)
        weekday.format(layout.firstMonday.add(Duration(days: i))),
    ];
    final labelWidth =
        weekdayLabels
            .map(
              (l) => (TextPainter(
                text: TextSpan(text: l, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
              )..layout()).width,
            )
            .fold<double>(0, math.max) +
        6;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - labelWidth;
        final cell = (available / layout.columns - _gap).clamp(12.0, 28.0);
        final width = layout.columns * (cell + _gap);
        final monthHeight = scaler.scale(style.fontSize ?? 11) * 1.4 + 4;
        final height = monthHeight + 7 * (cell + _gap);
        final max = days.fold(0, (m, d) => math.max(m, d.count));
        final colors = activityColors(theme.colorScheme);
        final selectedDay = selected;

        final grid = SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (final (col, label) in layout.monthStarts(month))
                Positioned(
                  left: col * (cell + _gap),
                  top: 0,
                  child: Text(label, style: style, textScaler: scaler),
                ),
              for (final d in days)
                () {
                  final (col, row) = layout.positionOf(d.day);
                  final isSelected = selectedDay == d.day;
                  return Positioned(
                    left: col * (cell + _gap),
                    top: monthHeight + row * (cell + _gap),
                    child: GestureDetector(
                      key: ValueKey('activity-day-${d.day.toIso8601String()}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(d.day),
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: colors[activityLevel(d.count, max)],
                          borderRadius: BorderRadius.circular(
                            math.min(4, cell / 4),
                          ),
                          border: isSelected
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 2,
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              height: height,
              child: Stack(
                children: [
                  for (var row = 0; row < 7; row++)
                    Positioned(
                      left: 0,
                      top: monthHeight + row * (cell + _gap),
                      height: cell,
                      child: Center(
                        child: Text(
                          weekdayLabels[row],
                          style: style,
                          textScaler: scaler,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: width <= available
                  ? Align(alignment: Alignment.centerLeft, child: grid)
                  // Empieza por hoy, a la derecha.
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: grid,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Dónde cae cada día en el calendario: la columna es la semana (de lunes a
/// domingo) y la fila, el día de la semana. Pública para probarla.
class CalendarLayout {
  CalendarLayout(this.days)
    : firstMonday = _mondayOf(days.isEmpty ? DateTime(2026) : days.first);

  final List<DateTime> days;

  /// El lunes de la semana del primer día, a medianoche.
  final DateTime firstMonday;

  static DateTime _mondayOf(DateTime day) =>
      DateTime(day.year, day.month, day.day - (day.weekday - 1));

  /// Cuántas semanas ocupa.
  int get columns => days.isEmpty ? 0 : positionOf(days.last).$1 + 1;

  /// La columna y la fila de [day]. Se cuentan fechas, no horas: el día del
  /// cambio de horario mide 23 o 25.
  (int, int) positionOf(DateTime day) {
    final from = DateTime.utc(
      firstMonday.year,
      firstMonday.month,
      firstMonday.day,
    );
    final to = DateTime.utc(day.year, day.month, day.day);
    final offset = to.difference(from).inDays;
    return (offset ~/ 7, day.weekday - 1);
  }

  /// Las columnas donde empieza un mes, con su nombre: la primera siempre, y
  /// después cada semana que trae un día 1. Una que quedaría pegada a la
  /// anterior (a menos de tres semanas) se saltea.
  List<(int, String)> monthStarts(DateFormat format) {
    final starts = <(int, String)>[];
    for (final (i, day) in days.indexed) {
      if (i != 0 && day.day != 1) continue;
      final entry = (positionOf(day).$1, format.format(day));
      if (starts.isNotEmpty && entry.$1 - starts.last.$1 < 3) {
        // El primer mes, si quedó corto, le deja el lugar al que empieza.
        if (starts.length == 1 && days.first.day != 1) starts[0] = entry;
        continue;
      }
      starts.add(entry);
    }
    return starts;
  }
}

// ── Las tarjetas difíciles ──────────────────────────────────────────────

class _HardestSection extends StatelessWidget {
  const _HardestSection({required this.cards});

  final List<DifficultCard> cards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatsSection(
      key: const Key('review-history-hardest'),
      title: l10n.reviewHistoryHardestCardsSectionTitle,
      subtitle: l10n.f43S20HardestSubtitle,
      child: cards.isEmpty
          ? _Muted(l10n.f43S20HardestEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final card in cards)
                  ListTile(
                    key: Key('hardest-card-${card.flashcardId}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      card.front,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_tally(l10n, card)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        unawaited(showDifficultCardSheet(context, card)),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    key: const Key('review-history-practice-hardest'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.replay),
                    label: Text(l10n.f43S20PracticeThese(cards.length)),
                    onPressed: () => unawaited(
                      context.push(
                        RoutePaths.reviewSessionFor(
                          practice: true,
                          cards: [for (final c in cards) c.flashcardId],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// «3 de 9 "De nuevo" · 2 lapsos».
String _tally(AppLocalizations l10n, DifficultCard card) => [
  l10n.f43S20HardestAgain(card.againCount, card.total),
  l10n.f43S20HardestLapses(card.lapses),
].join(' · ');

/// La hoja de una tarjeta difícil: la pregunta, la respuesta, sus números y
/// el camino a su fuente.
Future<void> showDifficultCardSheet(BuildContext context, DifficultCard card) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          key: const Key('difficult-card-sheet'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(card.front, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Text(card.back, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 16),
              Text(
                _tally(l10n, card),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('difficult-card-source'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(l10n.flashcardsViewSource),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        context.push(
                          card.hasSourceRange
                              ? RoutePaths.reading(
                                  card.itemId,
                                  start: card.sourceStart,
                                  end: card.sourceEnd,
                                )
                              : RoutePaths.itemDetail(card.itemId),
                        ),
                      );
                    },
                  ),
                  // La marca la pide así el encargo del paso 20, para
                  // encontrarla al integrar el paso 19.
                  // ignore: flutter_style_todos
                  // TODO(F43 M15): «Explicar» (`ExplainInChatButton`, del paso
                  // 19) con la pregunta y la respuesta de esta tarjeta; va
                  // acá, al lado de «Ver en la fuente», al integrar.
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
