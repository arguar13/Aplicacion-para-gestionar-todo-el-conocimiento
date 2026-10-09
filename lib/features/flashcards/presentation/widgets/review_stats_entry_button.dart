import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón que lleva a las estadísticas de repaso (F31, ola 2, decisión 72):
/// un ícono con su ayuda, para la barra de la sesión de repaso.
class ReviewStatsEntryButton extends StatelessWidget {
  const ReviewStatsEntryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('review-stats-entry'),
      icon: const Icon(Icons.insights_outlined),
      tooltip: l10n.cardStatsEntryTooltip,
      onPressed: () => context.push(kRouteReviewStats),
    );
  }
}
