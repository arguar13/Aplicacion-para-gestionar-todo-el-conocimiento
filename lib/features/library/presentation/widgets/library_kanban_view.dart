import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La biblioteca como un tablero, al estilo de una vista kanban de Notion:
/// una columna por espacio —más "Sin clasificar"—, con cada elemento como
/// una tarjeta que se arrastra de una columna a otra para cambiarle el
/// espacio.
///
/// Agrupa por espacio y no por otra propiedad porque es la única que ya
/// funciona como una clasificación exclusiva —un elemento pertenece a lo
/// sumo a un espacio, igual que a lo sumo a una columna de un tablero—; las
/// etiquetas se combinan entre sí y no tienen ese mismo encaje.
class LibraryKanbanView extends ConsumerWidget {
  const LibraryKanbanView({required this.items, super.key});

  final List<KnowledgeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final spaces = ref.watch(allSpacesProvider).valueOrNull ?? const <Space>[];

    final byUnclassified = items.where((i) => i.spaceId == null).toList();

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      children: [
        _KanbanColumn(
          title: l10n.detailSpaceNone,
          items: byUnclassified,
          targetSpaceId: null,
        ),
        for (final space in spaces)
          _KanbanColumn(
            title: space.name,
            items: items.where((i) => i.spaceId == space.id).toList(),
            targetSpaceId: space.id,
          ),
      ],
    );
  }
}

class _KanbanColumn extends ConsumerStatefulWidget {
  const _KanbanColumn({
    required this.title,
    required this.items,
    required this.targetSpaceId,
  });

  final String title;
  final List<KnowledgeItem> items;

  /// A qué espacio se asigna una tarjeta soltada acá. `null` es "sin
  /// clasificar", una asignación tan válida como cualquier otra.
  final String? targetSpaceId;

  @override
  ConsumerState<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends ConsumerState<_KanbanColumn> {
  var _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: _highlighted
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${widget.items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) {
                setState(() => _highlighted = true);
                return true;
              },
              onLeave: (_) => setState(() => _highlighted = false),
              onAcceptWithDetails: (details) {
                setState(() => _highlighted = false);
                ref
                    .read(libraryRepositoryProvider)
                    .assignSpace(
                      itemId: details.data,
                      spaceId: widget.targetSpaceId,
                    );
              },
              builder: (context, candidateData, rejectedData) =>
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) =>
                        _KanbanCard(item: widget.items[index]),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.item});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.push('${RoutePaths.library}/${item.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    item.source.kind.icon,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final tag in item.tags)
                      Chip(
                        label: Text(tag.name),
                        labelStyle: theme.textTheme.labelSmall,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<String>(
      data: item.id,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 240, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}
