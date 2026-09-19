import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/suggestion.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Las sugerencias de propiedad de toda la bóveda, agrupadas por lo que
/// proponen y revisables en lote: "14 elementos parecen ser `Región: Roma`".
///
/// Es lo que permite triar 30 elementos de golpe en vez de uno por uno, pero
/// el lote acelera la confirmación, no la quita: arranca sin nada marcado,
/// cada elemento se ve —con su título y el comienzo de su texto— y se marca
/// por separado, y nada se aplica sin que alguien lo haya marcado. Aplicar es
/// atómico: si una no se puede aplicar, ninguna queda aplicada.
class PropertySuggestionsReviewScreen extends ConsumerStatefulWidget {
  const PropertySuggestionsReviewScreen({super.key});

  @override
  ConsumerState<PropertySuggestionsReviewScreen> createState() =>
      _PropertySuggestionsReviewScreenState();
}

class _PropertySuggestionsReviewScreenState
    extends ConsumerState<PropertySuggestionsReviewScreen> {
  /// Los ids de las sugerencias marcadas.
  final _selected = <String>{};
  var _busy = false;

  Future<void> _apply(List<String> ids, {required bool accept}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(suggestionRepositoryProvider);
    setState(() => _busy = true);

    final result = accept
        ? await repository.acceptMany(ids)
        : await repository.rejectMany(ids);
    if (!mounted) return;
    setState(() => _busy = false);

    messenger.hideCurrentSnackBar();
    final failure = result.getLeft().toNullable();
    if (failure != null) {
      // Nada se aplicó: la selección queda para reintentar.
      messenger.showSnackBar(
        SnackBar(content: Text(failure.localizedMessage(l10n))),
      );
      return;
    }

    setState(() => _selected.removeAll(ids));
    final count = result.getRight().toNullable() ?? 0;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          accept
              ? l10n.suggestionReviewAccepted(count)
              : l10n.suggestionReviewRejected(count),
        ),
      ),
    );
  }

  void _toggleGroup(PropertySuggestionGroup group, {required bool select}) {
    setState(() {
      for (final suggestion in group.suggestions) {
        if (select) {
          _selected.add(suggestion.id);
        } else {
          _selected.remove(suggestion.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(pendingPropertySuggestionGroupsProvider);
    // Una sugerencia que ya se aplicó o se descartó desaparece de la lista: no
    // puede seguir marcada.
    final selected = _selected.intersection({
      for (final group
          in groups.valueOrNull ?? const <PropertySuggestionGroup>[])
        for (final suggestion in group.suggestions) suggestion.id,
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.suggestionReviewTitle)),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _CenteredMessage(l10n.suggestionReviewLoadError),
        data: (groups) => groups.isEmpty
            ? _CenteredMessage(l10n.suggestionReviewEmpty)
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: groups.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) return _Hint(l10n.suggestionReviewHint);
                        final group = groups[index - 1];
                        return _GroupTile(
                          group: group,
                          selected: selected,
                          enabled: !_busy,
                          initiallyExpanded: index == 1,
                          onToggleGroup: (select) =>
                              _toggleGroup(group, select: select),
                          onToggleOne: ({required id, required marked}) =>
                              setState(() {
                                if (marked) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                        );
                      },
                    ),
                  ),
                  if (selected.isNotEmpty)
                    _ActionBar(
                      count: selected.length,
                      busy: _busy,
                      onAccept: () => _apply(selected.toList(), accept: true),
                      onReject: () => _apply(selected.toList(), accept: false),
                    ),
                ],
              ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.enabled,
    required this.initiallyExpanded,
    required this.onToggleGroup,
    required this.onToggleOne,
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
      title: Text('${group.definitionName}: ${group.value}'),
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final int count;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: Text(l10n.suggestionReviewReject(count)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: Text(l10n.suggestionReviewAccept(count)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
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

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
