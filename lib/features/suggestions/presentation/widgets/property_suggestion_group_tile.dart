import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/i18n/category_label.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un grupo de sugerencias de propiedad —las que proponen el mismo valor de la
/// misma categoría— con sus elementos a la vista, para marcarlos uno por uno.
///
/// Lo usan la pantalla del lote y la hoja que la Bandeja abre sobre la tarjeta:
/// las dos revisan de la misma manera, así que las dos ven lo mismo. No decide
/// nada por su cuenta: solo muestra qué está marcado y avisa cuándo cambia.
class PropertySuggestionGroupTile extends StatelessWidget {
  const PropertySuggestionGroupTile({
    required this.group,
    required this.selected,
    required this.enabled,
    required this.initiallyExpanded,
    required this.onToggleGroup,
    required this.onToggleOne,
    super.key,
  });

  final PropertySuggestionGroup group;
  final Set<String> selected;
  final bool enabled;
  final bool initiallyExpanded;

  /// `true` marca todo el grupo; `false` lo desmarca.
  final ValueChanged<bool> onToggleGroup;
  final void Function({required String id, required bool marked}) onToggleOne;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final marked = group.suggestions.where((s) => selected.contains(s.id));
    final all = marked.length == group.suggestions.length;
    final none = marked.isEmpty;

    return ExpansionTile(
      key: PageStorageKey('${group.definitionId}/${group.normalizedValue}'),
      initiallyExpanded: initiallyExpanded,
      leading: Semantics(
        container: true,
        label: l10n.suggestionReviewSelectGroup,
        child: Checkbox(
          tristate: true,
          value: all
              ? true
              : none
              ? false
              : null,
          // Marcado del todo se desmarca; parcial o vacío, se marca entero.
          onChanged: enabled ? (_) => onToggleGroup(!all) : null,
        ),
      ),
      title: Text(
        '${categoryValueLabel(l10n, group.definitionName)}: ${group.value}',
      ),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.suggestionReviewGroupCount(group.suggestions.length)),
          if (!group.valueExists)
            Chip(
              label: Text(l10n.suggestionsNewValueBadge),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.tertiaryContainer,
              labelStyle: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
        ],
      ),
      children: [
        for (final suggestion in group.suggestions)
          _SuggestionRow(
            key: ValueKey(suggestion.id),
            suggestion: suggestion,
            selected: selected.contains(suggestion.id),
            enabled: enabled,
            onChanged: (value) => onToggleOne(id: suggestion.id, marked: value),
          ),
      ],
    );
  }
}

/// Una sugerencia con el elemento al que apunta a la vista: su título y el
/// comienzo de su texto, para decidir sin abrirlo.
class _SuggestionRow extends ConsumerWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final PropertySuggestion suggestion;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// El comienzo del texto, en una línea. Solo se muestra: no se guarda ni se
  /// resume nada.
  static String? _excerpt(KnowledgeItem item) {
    final text = item.searchableText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final item = ref
        .watch(libraryItemProvider(suggestion.targetItemId))
        .valueOrNull;
    final excerpt = item == null ? null : _excerpt(item);

    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        item?.title ?? '…',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: excerpt == null
          ? null
          : Text(excerpt, maxLines: 2, overflow: TextOverflow.ellipsis),
      secondary: IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: l10n.suggestionReviewOpenItem,
        onPressed: () =>
            context.push(RoutePaths.itemDetail(suggestion.targetItemId)),
      ),
    );
  }
}
