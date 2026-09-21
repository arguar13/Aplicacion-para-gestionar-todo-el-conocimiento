import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/domain/entities/tag.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/map/presentation/providers/map_filter_provider.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre el panel de filtros del mapa (F14, D8): tipo de elemento, tema de la
/// biblioteca, etiqueta y texto. Lo que se elija rige a las tres vistas.
Future<void> showMapFilters(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _MapFilterSheet(),
  );
}

class _MapFilterSheet extends ConsumerStatefulWidget {
  const _MapFilterSheet();

  @override
  ConsumerState<_MapFilterSheet> createState() => _MapFilterSheetState();
}

class _MapFilterSheetState extends ConsumerState<_MapFilterSheet> {
  late final _search = TextEditingController(
    text: ref.read(mapFilterProvider).searchText ?? '',
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filter = ref.watch(mapFilterProvider);
    final notifier = ref.read(mapFilterProvider.notifier);
    final tags = ref.watch(allTagsProvider).valueOrNull ?? const <Tag>[];
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];
    final active = activeMapFilters(filter);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.mapFiltersTooltip,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (active > 0)
                  TextButton(
                    key: const ValueKey('map-filter-clear'),
                    onPressed: () {
                      _search.clear();
                      notifier.clear();
                    },
                    child: Text(l10n.mapFilterClear),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('map-filter-search'),
              controller: _search,
              onChanged: notifier.search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.mapFilterSearchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(28)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Heading(l10n.mapFilterTypes),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in SourceKind.values)
                  FilterChip(
                    key: ValueKey('map-filter-kind-${kind.name}'),
                    avatar: Icon(kind.icon, size: 18),
                    label: Text(kind.label(l10n)),
                    selected: filter.sourceKinds.contains(kind),
                    onSelected: (_) => notifier.toggleSourceKind(kind),
                  ),
              ],
            ),
            if (spaces.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Heading(l10n.detailSpaceLabel),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final space in spaces)
                    FilterChip(
                      key: ValueKey('map-filter-space-${space.id}'),
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(space.name),
                      selected: filter.spaceId == space.id,
                      onSelected: (_) => notifier.toggleSpace(space.id),
                    ),
                ],
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Heading(l10n.mapFilterTags),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      key: ValueKey('map-filter-tag-${tag.id}'),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
