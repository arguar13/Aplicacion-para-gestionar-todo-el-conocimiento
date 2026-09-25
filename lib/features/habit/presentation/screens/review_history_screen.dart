import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/habit/domain/entities/daily_activity.dart';
import 'package:sinapsis/features/habit/domain/entities/difficult_card.dart';
import 'package:sinapsis/features/habit/domain/entities/review_history.dart';
import 'package:sinapsis/features/habit/domain/entities/weekly_retention.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El historial de repasos (F17, D8): curva de retención, calendario de
/// constancia y tarjetas difíciles, en ese orden —de lo más agregado a lo
/// más puntual—. Sin librería de gráficos: las tres se dibujan con
/// widgets propios.
class ReviewHistoryScreen extends ConsumerWidget {
  const ReviewHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref.watch(reviewHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewHistoryTitle)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.reviewHistoryLoadError)),
        data: (history) => _ReviewHistoryBody(history: history),
      ),
    );
  }
}

class _ReviewHistoryBody extends StatelessWidget {
  const _ReviewHistoryBody({required this.history});

  final ReviewHistory history;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasRetention = history.retentionByWeek.any((w) => w.total > 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(l10n.reviewHistoryRetentionSectionTitle),
        const SizedBox(height: 12),
        if (hasRetention)
          _RetentionChart(weeks: history.retentionByWeek)
        else
          _EmptyHint(l10n.reviewHistoryRetentionEmpty),
        const SizedBox(height: 28),
        _SectionTitle(l10n.reviewHistoryActivitySectionTitle),
        const SizedBox(height: 12),
        _ActivityCalendar(days: history.activityByDay),
        const SizedBox(height: 28),
        _SectionTitle(l10n.reviewHistoryHardestCardsSectionTitle),
        const SizedBox(height: 12),
        if (history.hardestCards.isEmpty)
          _EmptyHint(l10n.reviewHistoryHardestCardsEmpty)
        else
          _HardestCardsList(cards: history.hardestCards),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

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

/// Una barra por semana, alta según la proporción retenida —`good`/
/// `easy`—; una semana sin repasos queda como una marca chata y neutra,
/// no ausente: la fila sigue ahí.
class _RetentionChart extends StatelessWidget {
  const _RetentionChart({required this.weeks});

  final List<WeeklyRetention> weeks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SizedBox(
      key: const Key('review-history-retention-chart'),
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final week in weeks)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: l10n.reviewHistoryRetentionTooltip(
                    week.total,
                    (week.ratio * 100).round(),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor: week.total == 0
                        ? 0.03
                        : week.ratio.clamp(0.05, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: week.total == 0
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
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

/// Un día por celda, del más viejo al de hoy: más repasos, más intensa
/// —"como una racha de GitHub pero sin comparar con nadie" (D8)—.
class _ActivityCalendar extends StatelessWidget {
  const _ActivityCalendar({required this.days});

  final List<DailyActivity> days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final maxCount = days.fold(0, (m, d) => d.count > m ? d.count : m);

    return Wrap(
      key: const Key('review-history-activity-calendar'),
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final day in days)
          Tooltip(
            message: l10n.reviewHistoryActivityTooltip(day.count),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _colorFor(theme, day.count, maxCount),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }

  Color _colorFor(ThemeData theme, int count, int maxCount) {
    if (count == 0 || maxCount == 0) {
      return theme.colorScheme.surfaceContainerHighest;
    }
    return theme.colorScheme.primary.withValues(
      alpha: (count / maxCount).clamp(0.25, 1.0),
    );
  }
}

class _HardestCardsList extends StatelessWidget {
  const _HardestCardsList({required this.cards});

  final List<DifficultCard> cards;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
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
            trailing: Text(
              l10n.reviewHistoryHardestCardsAgainRatio(
                (card.againRatio * 100).round(),
              ),
            ),
          ),
      ],
    );
  }
}
