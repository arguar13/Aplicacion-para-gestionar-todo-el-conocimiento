import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/features/vocabulary/presentation/screens/vocabulary_value_screen.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/merge_confirm_dialog.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_feedback.dart';
import 'package:sinapsis/features/vocabulary/presentation/widgets/vocabulary_tree_view.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los valores de UNA categoría del vocabulario, con cuántos elementos tiene
/// cada uno: para buscar uno, renombrarlo, ver y manejar sus alias, y
/// fusionar varios en uno.
///
/// Con una categoría enorme —"Tema" puede juntar miles de valores— la lista
/// se construye de a poco y la búsqueda es lo que la vuelve manejable.
class VocabularyCategoryScreen extends ConsumerStatefulWidget {
  const VocabularyCategoryScreen({required this.definitionId, super.key});

  final String definitionId;

  @override
  ConsumerState<VocabularyCategoryScreen> createState() =>
      _VocabularyCategoryScreenState();
}

class _VocabularyCategoryScreenState
    extends ConsumerState<VocabularyCategoryScreen> {
  final TextEditingController _search = TextEditingController();

  /// Lo que se busca, ya normalizado —sin acentos ni mayúsculas—: buscar
  /// "cancion" tiene que encontrar "Canción".
  String _query = '';
  final Set<String> _selected = {};

  /// Cómo se ven los valores: como lista plana o, en una categoría de texto,
  /// como árbol de temas y subtemas (F13).
  bool _asTree = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _mergeSelected(List<VocabularyValueStat> chosen) async {
    // Antes de esperar nada: al terminar, esta pantalla puede haber cambiado.
    final feedback = VocabularyFeedback.of(context, ref);
    final controller = ref.read(vocabularyControllerProvider.notifier);

    final keepId = await showDialog<String>(
      context: context,
      builder: (context) => _ChooseKeepDialog(values: chosen),
    );
    if (keepId == null || !mounted) return;

    final keep = chosen.firstWhere((v) => v.id == keepId);
    final discardIds = [
      for (final value in chosen)
        if (value.id != keepId) value.id,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => MergeConfirmDialog(
        keepId: keep.id,
        keepLabel: keep.label,
        discardIds: discardIds,
      ),
    );
    if (confirmed != true) return;

    final result = await controller.merge(
      keepId: keep.id,
      discardIds: discardIds,
    );
    if (mounted && result.isRight()) setState(_selected.clear);
    feedback.report(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canUndo = ref.watch(vocabularyControllerProvider) != null;
    final values = ref.watch(categoryValuesProvider(widget.definitionId));
    final categoryName = ref
        .watch(vocabularyCategoryStatsProvider)
        .valueOrNull
        ?.where((c) => c.id == widget.definitionId)
        .firstOrNull
        ?.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName ?? l10n.vocabularyTitle),
        actions: [
          IconButton(
            tooltip: l10n.vocabularyUndoTooltip,
            icon: const Icon(Icons.undo),
            onPressed: canUndo
                ? VocabularyFeedback.of(context, ref).undo
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.vocabularySearchHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (text) =>
                  setState(() => _query = normalizeVocabularyLabel(text)),
            ),
          ),
          Expanded(
            child: values.when(
              error: (_, _) => Center(child: Text(l10n.vocabularyLoadError)),
              loading: () => const Center(child: CircularProgressIndicator()),
              data: (all) {
                if (all.isEmpty) {
                  return Center(child: Text(l10n.vocabularyCategoryEmpty));
                }
                final shown = _query.isEmpty
                    ? all
                    : [
                        for (final v in all)
                          if (normalizeVocabularyLabel(
                            v.label,
                          ).contains(_query))
                            v,
                      ];
                if (shown.isEmpty) {
                  return Center(child: Text(l10n.vocabularySearchNoResults));
                }

                // Solo las categorías de texto tienen jerarquía; y buscando, la
                // lista plana encuentra a un valor esté donde esté.
                final canBeTree = all.first.isText;
                if (canBeTree && _asTree && _query.isEmpty) {
                  return Column(
                    children: [
                      _ViewToggle(
                        asTree: true,
                        onChanged: (asTree) => setState(() => _asTree = asTree),
                      ),
                      Expanded(
                        child: VocabularyTreeView(
                          values: all,
                          onOpen: (valueId) => openVocabularyValue(
                            context,
                            definitionId: widget.definitionId,
                            valueId: valueId,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Lo marcado que ya no existe —se fusionó, se borró— se
                // olvida solo.
                final present = all.map((v) => v.id).toSet();
                final selected = _selected.intersection(present);
                final chosen = [
                  for (final v in all)
                    if (selected.contains(v.id)) v,
                ];

                return Column(
                  children: [
                    if (canBeTree)
                      _ViewToggle(
                        asTree: false,
                        onChanged: (asTree) => setState(() => _asTree = asTree),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final value = shown[index];
                          return ListTile(
                            leading: Checkbox(
                              value: selected.contains(value.id),
                              onChanged: (checked) => setState(() {
                                if (checked ?? false) {
                                  _selected.add(value.id);
                                } else {
                                  _selected.remove(value.id);
                                }
                              }),
                            ),
                            title: Text(value.label),
                            subtitle: Text(
                              [
                                l10n.vocabularyUsage(value.usage),
                                if (value.aliasCount > 0)
                                  l10n.vocabularyAliasCount(value.aliasCount),
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openVocabularyValue(
                              context,
                              definitionId: widget.definitionId,
                              valueId: value.id,
                            ),
                          );
                        },
                      ),
                    ),
                    // Fusionar necesita al menos dos.
                    if (chosen.length >= 2)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => _mergeSelected(chosen),
                              child: Text(
                                l10n.vocabularyMergeSelected(chosen.length),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// El selector entre la lista plana y el árbol.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.asTree, required this.onChanged});

  final bool asTree;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.view_list),
            label: Text(l10n.vocabularyViewList),
          ),
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.account_tree),
            label: Text(l10n.vocabularyViewTree),
          ),
        ],
        selected: {asTree},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// Pide cuál de los valores marcados se conserva; los demás pasan a él. Por
/// defecto, el más usado. Devuelve su id, o `null` si se canceló.
class _ChooseKeepDialog extends StatefulWidget {
  const _ChooseKeepDialog({required this.values});

  final List<VocabularyValueStat> values;

  @override
  State<_ChooseKeepDialog> createState() => _ChooseKeepDialogState();
}

class _ChooseKeepDialogState extends State<_ChooseKeepDialog> {
  late final List<VocabularyValueStat> _ordered = [...widget.values]
    ..sort((a, b) {
      final byUsage = b.usage.compareTo(a.usage);
      if (byUsage != 0) return byUsage;
      final byLength = a.label.length.compareTo(b.label.length);
      if (byLength != 0) return byLength;
      return a.id.compareTo(b.id);
    });

  late String _keepId = _ordered.first.id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.vocabularyChooseKeepTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.vocabularyChooseKeepBody),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final value in _ordered)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        value.id == _keepId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: value.id == _keepId
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(value.label),
                      subtitle: Text(l10n.vocabularyUsage(value.usage)),
                      onTap: () => setState(() => _keepId = value.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_keepId),
          child: Text(l10n.vocabularyMergeConfirmAction),
        ),
      ],
    );
  }
}
