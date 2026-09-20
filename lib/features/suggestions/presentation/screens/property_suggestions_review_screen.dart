import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/suggestions/domain/entities/property_suggestion_group.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_batch_actions.dart';
import 'package:sinapsis/features/suggestions/presentation/widgets/property_suggestion_group_tile.dart';
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
    final repository = ref.read(suggestionRepositoryProvider);
    setState(() => _busy = true);

    final count = await applyPropertySuggestionBatch(
      context: context,
      repository: repository,
      ids: ids,
      accept: accept,
    );
    if (!mounted) return;

    // Si nada se aplicó, la selección queda para reintentar.
    setState(() {
      _busy = false;
      if (count != null) _selected.removeAll(ids);
    });
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
                        return PropertySuggestionGroupTile(
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
