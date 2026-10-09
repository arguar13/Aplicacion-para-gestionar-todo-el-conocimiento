import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/flashcards/domain/entities/review_stats.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/review_stats_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_buttons.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_distribution.dart';
import 'package:sinapsis/features/flashcards/presentation/widgets/card_stats_forecast.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/features/habit/presentation/screens/review_history_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las estadísticas de repaso (F31, ola 2, decisión 72): lo que ya había
/// —racha, insignias, constancia, curva de retención y las más difíciles
/// (F17), que se reutilizan tal cual— y lo nuevo: el pronóstico de los
/// próximos 30 días, el reparto por etapa y los botones apretados.
///
/// Sin librería de gráficos: se dibujan con widgets, en claro y en oscuro.
class ReviewStatsScreen extends ConsumerStatefulWidget {
  const ReviewStatsScreen({super.key});

  @override
  ConsumerState<ReviewStatsScreen> createState() => _ReviewStatsScreenState();
}

class _ReviewStatsScreenState extends ConsumerState<ReviewStatsScreen> {
  var _period = StatsPeriod.days30;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stats = ref.watch(reviewStatsProvider(_period));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cardStatsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StreakHeader(),
          const SizedBox(height: 24),
          stats.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Text(
              l10n.cardStatsLoadError,
              key: const Key('card-stats-error'),
            ),
            data: (data) => _Sections(
              stats: data,
              period: _period,
              onPeriod: (period) => setState(() => _period = period),
            ),
          ),
          const SizedBox(height: 28),
          const ReviewHistorySectionsView(),
        ],
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({
    required this.stats,
    required this.period,
    required this.onPeriod,
  });

  final ReviewStats stats;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = Theme.of(context).textTheme.titleMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.cardStatsForecastTitle, style: title),
        const SizedBox(height: 12),
        CardStatsForecast(forecast: stats.forecast),
        const SizedBox(height: 28),
        Text(l10n.cardStatsDistributionTitle, style: title),
        const SizedBox(height: 12),
        CardStatsDistribution(distribution: stats.distribution),
        const SizedBox(height: 28),
        Text(l10n.cardStatsButtonsTitle, style: title),
        const SizedBox(height: 4),
        Text(
          l10n.cardStatsButtonsSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        CardStatsButtons(
          usage: stats.buttons,
          period: period,
          onPeriod: onPeriod,
        ),
      ],
    );
  }
}

/// La racha y el camino a las insignias: lo de F17, que ya se leía de
/// `currentStreakProvider`.
class _StreakHeader extends ConsumerWidget {
  const _StreakHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final streak = ref.watch(currentStreakProvider).valueOrNull;
    final days = streak?.days ?? 0;
    final color = streak != null && streak.activeToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Icon(Icons.local_fire_department, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.cardStatsStreakDays(days),
            key: const Key('card-stats-streak'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          key: const Key('card-stats-badges'),
          icon: const Icon(Icons.military_tech_outlined),
          label: Text(l10n.cardStatsBadgesAction),
          onPressed: () => context.push(RoutePaths.reviewBadges),
        ),
      ],
    );
  }
}
