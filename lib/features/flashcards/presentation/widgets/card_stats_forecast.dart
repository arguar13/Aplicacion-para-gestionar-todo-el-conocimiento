import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El pronóstico de los próximos 30 días de estudio (F31, ola 2, decisión 72):
/// una columna por día —el de hoy primero, con lo atrasado—, alta según cuántas
/// vencen.
///
/// Un solo tono (el del tema), una sola escala desde cero —la altura es la
/// cantidad, sin cortar el eje—, la grilla casi invisible y dos números a la
/// vista: lo de hoy y el pico. Cada columna tiene su ayuda con la fecha y la
/// cuenta; la vista de tabla («Ver los números») lista los 30 días para quien
/// no lee el gráfico.
class CardStatsForecast extends StatelessWidget {
  const CardStatsForecast({required this.forecast, super.key});

  final ReviewForecast forecast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.MMMEd(locale);
    final today = forecast.days.first;
    final peak = forecast.peak;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (forecast.total == 0) {
      return Text(
        l10n.cardStatsForecastEmpty,
        key: const Key('card-stats-forecast-empty'),
        style: muted,
      );
    }

    final summary = [
      l10n.cardStatsForecastToday(today.count),
      if (forecast.overdue > 0) l10n.cardStatsForecastOverdue(forecast.overdue),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary, key: const Key('card-stats-forecast-today')),
        Text(
          l10n.cardStatsForecastTotal(forecast.total),
          key: const Key('card-stats-forecast-total'),
          style: muted,
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          label: l10n.cardStatsForecastChartLabel(forecast.total, peak),
          // Las columnas hablan una por una con su ayuda; el gráfico entero,
          // con este resumen.
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cardStatsForecastPeak(peak),
                key: const Key('card-stats-forecast-peak'),
                style: muted,
              ),
              const SizedBox(height: 4),
              SizedBox(
                key: const Key('card-stats-forecast-chart'),
                height: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.colorScheme.outline),
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (index, day) in forecast.days.indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Tooltip(
                              message: l10n.cardStatsForecastBar(
                                date.format(day.start),
                                day.count,
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor: day.count == 0
                                    ? 0.02
                                    : day.count / peak,
                                child: DecoratedBox(
                                  key: Key('card-stats-forecast-bar-$index'),
                                  decoration: BoxDecoration(
                                    color: day.count == 0
                                        ? theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                        : theme.colorScheme.primary,
                                    // Redondeo solo en el extremo del dato,
                                    // pegado a la línea de base.
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final (label, align) in [
                    (l10n.cardStatsForecastAxisToday, TextAlign.start),
                    (
                      l10n.cardStatsForecastAxisDays(forecast.days.length ~/ 2),
                      TextAlign.center,
                    ),
                    (
                      l10n.cardStatsForecastAxisDays(forecast.days.length - 1),
                      TextAlign.end,
                    ),
                  ])
                    Expanded(
                      child: Text(
                        label,
                        textAlign: align,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        ExpansionTile(
          key: const Key('card-stats-forecast-table'),
          tilePadding: EdgeInsets.zero,
          title: Text(l10n.cardStatsForecastTable),
          children: [
            for (final day in forecast.days)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(date.format(day.start)),
                trailing: Text('${day.count}'),
              ),
          ],
        ),
      ],
    );
  }
}
