import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el panel de filtros de la línea de tiempo: tipo de elemento y tema.
Future<void> showTimelineFilters(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _TimelineFilterSheet(),
  );
}

class _TimelineFilterSheet extends ConsumerWidget {
  const _TimelineFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filter = ref.watch(timelineFilterProvider);
    final notifier = ref.read(timelineFilterProvider.notifier);
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];
    final hasKindOrTag =
        filter.sourceKinds.isNotEmpty || filter.tagIds.isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.timelineFiltersTooltip,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (hasKindOrTag)
                  TextButton(
                    onPressed: notifier.clear,
                    child: Text(l10n.timelineFilterClear),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.timelineFilterTypes,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in SourceKind.values)
                  FilterChip(
                    avatar: Icon(kind.icon, size: 18),
                    label: Text(kind.label(l10n)),
                    selected: filter.sourceKinds.contains(kind),
                    onSelected: (_) => notifier.toggleSourceKind(kind),
                  ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.timelineFilterTopics,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag.name),
                      selected: filter.tagIds.contains(tag.id),
                      onSelected: (_) => notifier.toggleTagId(tag.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
