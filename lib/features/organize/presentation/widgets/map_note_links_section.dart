import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relations_section.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La misma lista de vínculos que [RelationsSection], pero agrupada por
/// [RelationKind] en vez de en el orden cronológico plano.
///
/// Es la "vista propia" que pide una nota mapa (decisión D3 de F6, ver
/// `docs/arquitectura.md`): el grafo local ya se embebe en el detalle de
/// cualquier elemento, así que lo que la distingue no es un segundo
/// grafo sino cómo se lee esta lista.
class MapNoteLinksSection extends ConsumerWidget {
  const MapNoteLinksSection({required this.item, super.key});

  final KnowledgeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final relations =
        ref.watch(itemRelationsProvider(item.id)).valueOrNull ??
        const <ItemRelation>[];

    final grouped = <RelationKind, List<ItemRelation>>{};
    for (final relation in relations) {
      grouped.putIfAbsent(relation.kind, () => []).add(relation);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.detailRelationsTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: l10n.detailAddRelation,
              onPressed: () =>
                  addRelationFlow(context, ref, fromItemId: item.id),
            ),
          ],
        ),
        for (final kind in RelationKind.values)
          if (grouped.containsKey(kind)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                kind.shortLabel(l10n),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final relation in grouped[kind]!)
              RelationTile(
                relation: relation,
                onDelete: () => ref
                    .read(organizeRepositoryProvider)
                    .deleteRelation(relation.relationId),
              ),
          ],
      ],
    );
  }
}
