import 'package:flutter/material.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_gap.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/atlas_labels.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuántos vacíos se listan como mucho: con miles de temas, los de «un solo
/// elemento» pueden ser cientos, y una lista que no se termina no orienta a
/// nadie. Van primero los que más importan; el resto se cuenta.
const kMaxGapsShown = 30;

/// Los vacíos detectados en el Atlas (F13, D7): temas con mucho material y
/// nada propio escrito, ramas con un solo elemento, ramas que nadie tocó hace
/// meses.
///
/// Cada uno se toca para ir a lo que lo resuelve: el material de esa rama, en
/// el Explorador.
class GapsCard extends StatelessWidget {
  const GapsCard({
    required this.snapshot,
    required this.now,
    required this.onOpen,
    super.key,
  });

  final AtlasSnapshot snapshot;

  /// El momento de ahora, para decir hace cuánto que no se toca una rama.
  final DateTime now;

  /// Se abre el material de la rama con ese valor.
  final void Function(String valueId) onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final gaps = snapshot.gaps;
    final shown = gaps.take(kMaxGapsShown).toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ExpansionTile(
        key: const ValueKey('atlas-gaps'),
        leading: Icon(Icons.flag_outlined, color: theme.colorScheme.tertiary),
        title: Text(l10n.atlasGapsTitle(gaps.length)),
        // Pocos, a la vista; muchos, plegados: el árbol es lo principal.
        initiallyExpanded: gaps.length <= 5,
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          for (final gap in shown)
            _GapTile(
              gap: gap,
              node: snapshot.nodeOf(gap.valueId),
              now: now,
              onOpen: onOpen,
            ),
          if (gaps.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                l10n.atlasGapsMore(gaps.length - shown.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GapTile extends StatelessWidget {
  const _GapTile({
    required this.gap,
    required this.node,
    required this.now,
    required this.onOpen,
  });

  final AtlasGap gap;
  final AtlasNode? node;
  final DateTime now;
  final void Function(String valueId) onOpen;

  IconData get _icon => switch (gap.kind) {
    AtlasGapKind.manySourcesNoLivingNote => Icons.library_books_outlined,
    AtlasGapKind.singleItem => Icons.looks_one_outlined,
    AtlasGapKind.stale => Icons.history_toggle_off,
  };

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    // Un vacío de una rama que ya no está: no hay a dónde llevar.
    if (node == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      key: ValueKey('atlas-gap-${gap.kind.name}-${gap.valueId}'),
      leading: Icon(_icon),
      title: Text(node.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(atlasGapMessage(l10n, gap, node, now)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(gap.valueId),
    );
  }
}
