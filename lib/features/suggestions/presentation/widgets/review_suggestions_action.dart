import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El acceso a la revisión en lote de las sugerencias de propiedad, con
/// cuántas hay pendientes. No ocupa lugar si no hay ninguna.
///
/// Un widget aparte porque lo usan la Bandeja y el panel de salud.
class ReviewSuggestionsAction extends ConsumerWidget {
  const ReviewSuggestionsAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(pendingPropertySuggestionGroupsProvider);
    final count = (groups.valueOrNull ?? const []).fold<int>(
      0,
      (total, group) => total + group.suggestions.length,
    );
    if (count == 0) return const SizedBox.shrink();

    return IconButton(
      tooltip: l10n.suggestionReviewOpenTooltip(count),
      icon: Badge(label: Text('$count'), child: const Icon(Icons.checklist)),
      onPressed: () => context.push(RoutePaths.suggestionReview),
    );
  }
}
