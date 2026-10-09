import 'package:flutter/material.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_palette.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se reparten las tarjetas entre nuevas, aprendiendo, jóvenes, maduras y
/// pausadas (F31, ola 2, decisión 72): una barra apilada de punta a punta y,
/// debajo, cada etapa con su cuenta y su porcentaje.
///
/// La leyenda siempre está: el color nunca es lo único que dice qué es cada
/// tramo, y la lista es también la vista de números.
class CardStatsDistribution extends StatelessWidget {
  const CardStatsDistribution({required this.distribution, super.key});

  final CardDistribution distribution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = CardStatsPalette.of(context);
    final total = distribution.total;

    if (total == 0) {
      return Text(
        l10n.cardStatsDistributionEmpty,
        key: const Key('card-stats-distribution-empty'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cardStatsDistributionTotal(total),
          key: const Key('card-stats-distribution-total'),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: SizedBox(
            key: const Key('card-stats-distribution-bar'),
            height: 20,
            child: Row(
              children: [
                for (final (key, _, count, color) in parts)
                  if (count > 0)
                    Expanded(
                      flex: count,
                      child: Padding(
                        // Dos píxeles de fondo entre tramos, no un borde.
                        padding: const EdgeInsets.only(right: 2),
                        child: DecoratedBox(
                          key: Key('card-stats-distribution-segment-$key'),
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
        ),
        const SizedBox(height: 12),
        for (final (key, label, count, color) in parts)
          Padding(
            key: Key('card-stats-distribution-row-$key'),
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Semantics(
              label: l10n.cardStatsDistributionRow(
                label,
                count,
                (count * 100 / total).round(),
              ),
              excludeSemantics: true,
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
                  Text('$count', style: theme.textTheme.titleSmall),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(count * 100 / total).round()} %',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
