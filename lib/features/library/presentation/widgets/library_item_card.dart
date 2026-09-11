import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de la biblioteca.
///
/// Muestra cuatro cosas y en este orden de importancia: qué es (el ícono del
/// tipo de fuente), cómo se llama, de dónde salió y si le falta algo. Un
/// vistazo a la lista tiene que alcanzar para reconocer lo que uno busca.
class LibraryItemCard extends StatelessWidget {
  const LibraryItemCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
    super.key,
  });

  final KnowledgeItem item;
  final VoidCallback onTap;

  /// Punto de entrada al modo de selección múltiple, en las listas donde
  /// existe. `null` en las que no lo ofrecen.
  final VoidCallback? onLongPress;

  /// Si la lista está mostrando casillas en vez de navegar al tocar.
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final stateLabel = item.processingState.label(l10n);

    return ListTile(
      // En modo selección, tocar la fila alterna la casilla: es lo que
      // espera cualquiera que use Gmail o Fotos, y repetir el mismo gesto
      // en la casilla y en el resto de la fila evita que haya que acertarle
      // a un blanco chico.
      onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
      onLongPress: onLongPress,
      selected: selected,
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (value) => onSelectedChanged?.call(value ?? false),
            )
          : Icon(
              item.source.kind.icon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              item.subtitle ?? item.source.kind.label(l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (stateLabel != null) ...[
            const SizedBox(width: 8),
            _StateBadge(
              label: stateLabel,
              color: item.processingState.color(theme.colorScheme)!,
            ),
          ],
        ],
      ),
    );
  }
}

/// La insignia de estado. Solo aparece cuando hay algo que decir — ver
/// `ProcessingStatePresentation.label`.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
