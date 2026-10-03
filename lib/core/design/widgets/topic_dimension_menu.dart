import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/topic_dimension.dart';
import 'package:sinapsis/core/i18n/category_label.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cómo se llama una dimensión en la interfaz (F28): «Temas», «Etiquetas» —la
/// categoría de sistema que en la base se sigue llamando «Tema»— o el nombre
/// de la categoría.
String topicDimensionLabel(AppLocalizations l10n, TopicDimension dimension) {
  final category = dimension.category;
  if (category == null) return l10n.topicDimensionSpaces;
  return categoryLabel(l10n, category.name);
}

/// Qué clase de cosa agrupa [dimension], como la piden los textos que cambian
/// según lo que se mira —«Temas aislados», «Etiquetas aisladas», «Valores
/// aislados»—: `spaces`, `tags` u `other`.
String topicSelectKind(TopicDimension dimension) {
  if (dimension.isSpaces) return 'spaces';
  if (dimension.isTags) return 'tags';
  return 'other';
}

/// El ícono de una dimensión: una carpeta para los temas —son carpetas: uno
/// por elemento—, una etiqueta para las etiquetas y una categoría para las
/// demás.
IconData topicDimensionIcon(TopicDimension dimension) {
  if (dimension.isSpaces) return Icons.folder_outlined;
  if (dimension.isTags) return Icons.label_outline;
  return Icons.category_outlined;
}

/// El selector de por qué agrupan el Mapa y el Atlas (F28), a la vista: una
/// ficha con la dimensión de ahora que abre las demás. A la vista y no
/// escondido en un ícono de la barra, porque decide qué se está mirando.
class TopicDimensionMenu extends StatelessWidget {
  const TopicDimensionMenu({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<TopicDimension> options;
  final TopicDimension selected;
  final ValueChanged<TopicDimension> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = topicDimensionLabel(l10n, selected);

    return PopupMenuButton<TopicDimension>(
      tooltip: l10n.topicDimensionTooltip,
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            key: ValueKey('topic-dimension-${option.id}'),
            value: option,
            child: Row(
              children: [
                Icon(topicDimensionIcon(option), size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(topicDimensionLabel(l10n, option))),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: '${l10n.topicDimensionTooltip}: $label',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  topicDimensionIcon(selected),
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
