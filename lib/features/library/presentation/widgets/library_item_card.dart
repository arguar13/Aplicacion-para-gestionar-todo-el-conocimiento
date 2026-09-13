import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de la biblioteca.
///
/// Muestra cuatro cosas y en este orden de importancia: qué es (el ícono del
/// tipo de fuente), cómo se llama, de dónde salió y si le falta algo. Un
/// vistazo a la lista tiene que alcanzar para reconocer lo que uno busca.
///
/// Tarjeta propia y no `ListTile` a secas: una superficie con esquinas
/// redondeadas y aire alrededor separa visualmente cada elemento sin
/// necesitar una línea divisoria, y dan lugar a un ícono con más presencia
/// —el mismo criterio que el ícono de una página en Notion—.
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
    final colors = theme.colorScheme;
    final stateLabel = item.processingState.label(l10n);

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.4)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // En modo selección, tocar la fila alterna la casilla: es lo que
        // espera cualquiera que use Gmail o Fotos, y repetir el mismo gesto
        // en la casilla y en el resto de la fila evita que haya que
        // acertarle a un blanco chico.
        onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? colors.primary
                  : colors.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2),
                  child: Checkbox(
                    value: selected,
                    onChanged: (value) =>
                        onSelectedChanged?.call(value ?? false),
                  ),
                )
              else
                _IconBadge(icon: item.source.kind.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.subtitle ?? item.source.kind.label(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (stateLabel != null) ...[
                          const SizedBox(width: 8),
                          _StateBadge(
                            label: stateLabel,
                            color: item.processingState.color(colors)!,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El ícono del tipo de fuente, con más presencia que un ícono suelto: un
/// fondo circular tenue lo separa del texto y le da al ojo un punto de
/// anclaje fijo por el que reconocer la fila, aunque el título cambie de
/// largo entre una y otra.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
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
