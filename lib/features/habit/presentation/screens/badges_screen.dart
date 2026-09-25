import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/habit/domain/entities/badge_kind.dart';
import 'package:sinapsis/features/habit/presentation/providers/habit_providers.dart';
import 'package:sinapsis/features/habit/presentation/widgets/badge_kind_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las seis insignias de F17, D7 —premian destilar, consolidar y repasar,
/// nunca capturar—. Se muestran siempre las seis, ganadas o no: ver lo que
/// falta es parte del punto, no solo una lista de trofeos.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final earned = ref.watch(earnedBadgesProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.habitBadgesTitle)),
      body: ListView.builder(
        itemCount: BadgeKind.values.length,
        itemBuilder: (context, index) {
          final kind = BadgeKind.values[index];
          return _BadgeTile(kind: kind, earned: earned.contains(kind));
        },
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.kind, required this.earned});

  final BadgeKind kind;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = earned
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Opacity(
      opacity: earned ? 1 : 0.6,
      child: ListTile(
        key: Key('badge-${kind.name}'),
        leading: Icon(kind.icon, color: color),
        title: Text(kind.label(l10n)),
        subtitle: Text(kind.description(l10n)),
        trailing: earned
            ? Text(
                l10n.habitBadgeEarnedLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              )
            : null,
      ),
    );
  }
}
