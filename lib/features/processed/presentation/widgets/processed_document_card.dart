import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';
import 'package:sinapsis/features/processed/presentation/widgets/processed_section_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Una fila de «Procesado» (F41): el ícono de la fuente de la que salió, el
/// título, las partes que tiene y cuándo se actualizó.
///
/// Se ve como una fila de la Biblioteca —`LibraryItemCard`: la misma
/// superficie, el mismo contorno y el mismo gesto para elegir de a varios—,
/// con el lenguaje de una nota (`EntityRole.note`, esquinas redondeadas y el
/// color de las notas): lo procesado es lo que la persona sacó, no algo que
/// trajo de afuera. Nada de acá mide lo que mide el texto: la fila de un libro
/// cuesta lo mismo que la de una nota.
class ProcessedDocumentCard extends StatelessWidget {
  const ProcessedDocumentCard({
    required this.document,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
    super.key,
  });

  final ProcessedDocumentSummary document;
  final VoidCallback onTap;

  /// La entrada al modo de selección múltiple.
  final VoidCallback? onLongPress;

  /// Si la lista muestra casillas en vez de abrir al tocar.
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const role = EntityRole.note;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final updated = l10n.processedUpdatedOn(
      DateFormat.yMMMd(locale).format(document.updatedAt.toLocal()),
    );
    final sections = document.sections;

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.4)
          : role.surface(colors),
      borderRadius: BorderRadius.circular(role.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(role.radius),
        // En modo selección, tocar la fila alterna la casilla: el mismo
        // gesto que en la Biblioteca.
        onTap: selectionMode ? () => onSelectedChanged?.call(!selected) : onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(role.radius),
            border: Border.all(
              color: selected ? colors.primary : role.outline(colors),
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
                _OriginBadge(document: document),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (sections.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // Para el lector de pantalla, las partes en una sola
                      // frase y no chip por chip.
                      Semantics(
                        label: l10n.processedRowParts(
                          sections.map((s) => s.label(l10n)).join(', '),
                        ),
                        excludeSemantics: true,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final section in sections)
                              _PartChip(section: section),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      updated,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
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

/// El ícono del tipo de la fuente de la que salió, sobre el tono de las notas.
class _OriginBadge extends StatelessWidget {
  const _OriginBadge({required this.document});

  final ProcessedDocumentSummary document;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: document.sourceKind.label(l10n),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          document.sourceKind.icon,
          color: colors.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// Una parte que tiene el documento: un chip quieto, sin toque propio —tocar
/// la fila abre el documento—.
class _PartChip extends StatelessWidget {
  const _PartChip({required this.section});

  final ProcessedSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                section.label(l10n),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
