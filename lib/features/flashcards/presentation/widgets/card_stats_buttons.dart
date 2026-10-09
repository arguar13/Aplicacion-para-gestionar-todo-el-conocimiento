import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_palette.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Qué botones se apretaron en cada etapa (F31, ola 2, decisión 72): por etapa
/// y en total, una barra de «De nuevo / Difícil / Bien / Fácil» y el porcentaje
/// de acierto —lo que no fue «De nuevo»—. El período se elige arriba.
///
/// Sin respuestas en una etapa no hay barra ni porcentaje: «sin datos» no es
/// «0 % de acierto». No hay tiempo estudiado: `review_log` no guarda cuánto se
/// tardó, y no se inventa.
class CardStatsButtons extends StatelessWidget {
  const CardStatsButtons({
    required this.usage,
    required this.period,
    required this.onPeriod,
    super.key,
  });

  final ButtonUsageByStage usage;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<StatsPeriod>(
          key: const Key('card-stats-period'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: StatsPeriod.days30,
              label: Text(l10n.cardStatsPeriod30),
            ),
            ButtonSegment(
              value: StatsPeriod.days90,
              label: Text(l10n.cardStatsPeriod90),
            ),
            ButtonSegment(
              value: StatsPeriod.all,
              label: Text(l10n.cardStatsPeriodAll),
            ),
          ],
          selected: {period},
          onSelectionChanged: (picked) => onPeriod(picked.first),
        ),
        const SizedBox(height: 16),
        if (usage.overall.total == 0)
          Text(
            l10n.cardStatsButtonsEmpty,
            key: const Key('card-stats-buttons-empty'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final (key, label, stageUsage) in stages)
            _StageRow(keyName: key, label: label, usage: stageUsage),
      ],
    );
  }
}

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
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )
                  : Row(
                      children: [
                        for (final (gradeKey, _, count, color) in grades)
                          if (count > 0)
                            Expanded(
                              flex: count,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: DecoratedBox(
                                  key: Key(
                                    'card-stats-buttons-segment-$keyName-'
                                    '$gradeKey',
                                  ),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (final (_, gradeLabel, count, color) in grades)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$gradeLabel $count',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
